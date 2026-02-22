use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use futures_util::{SinkExt, StreamExt};
use moo_core::classify_line;
use serde::{Deserialize, Serialize};
use tokio::io::{self, AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;
use tokio::time::{sleep, Duration};
use tokio_tungstenite::{connect_async, tungstenite::Message};

#[derive(Parser, Debug)]
#[command(name = "moo-cli")]
#[command(about = "Debug-first CLI for moo-client proxy")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Connect to a proxy websocket endpoint and run interactive mode.
    Connect {
        #[arg(long, default_value = "ws://127.0.0.1:9000/ws")]
        ws_url: String,

        #[arg(long)]
        session_id: Option<String>,

        #[arg(long)]
        resume_offset: Option<u64>,

        #[arg(long)]
        state_file: Option<PathBuf>,

        #[arg(long)]
        no_resume: bool,

        #[arg(long)]
        raw: bool,

        #[arg(long)]
        json: bool,

        #[arg(long)]
        trace: bool,
    },

    /// Run scripted scenario mode (for deterministic smoke/CI checks).
    Scenario {
        #[arg(long, default_value = "ws://127.0.0.1:9000/ws")]
        ws_url: String,

        #[arg(long)]
        session_id: Option<String>,

        #[arg(long)]
        resume_offset: Option<u64>,

        #[arg(long)]
        state_file: Option<PathBuf>,

        #[arg(long)]
        no_resume: bool,

        #[arg(long)]
        raw: bool,

        #[arg(long)]
        json: bool,

        #[arg(long)]
        trace: bool,

        #[arg(long)]
        scenario_file: PathBuf,

        #[arg(long, default_value_t = 250)]
        step_ms: u64,
    },
}

#[derive(Debug)]
enum Outbound {
    RawLine(String),
    Quit,
}

#[derive(Debug)]
enum Command {
    Send(String),
    Ping,
    Offset,
    Wait(u64),
    Resume(u64),
    Reconnect(Option<u64>),
    Quit,
    Unknown(String),
}

#[derive(Debug)]
enum LoopControl {
    Exit,
    Reconnect,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PersistedState {
    session_id: String,
    last_offset: u64,
}

#[derive(Debug, Clone)]
struct SessionState {
    session_id: String,
    current_offset: u64,
}

#[derive(Debug)]
struct ConnectConfig {
    ws_url: String,
    session_id: Option<String>,
    resume_offset: Option<u64>,
    state_file: Option<PathBuf>,
    no_resume: bool,
    raw: bool,
    json: bool,
    trace: bool,
}

enum InputMode {
    Stdin,
    Scenario { lines: Vec<String>, step_ms: u64 },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    let result = match cli.command {
        Commands::Connect {
            ws_url,
            session_id,
            resume_offset,
            state_file,
            no_resume,
            raw,
            json,
            trace,
        } => {
            run_connect(
                ConnectConfig {
                    ws_url,
                    session_id,
                    resume_offset,
                    state_file,
                    no_resume,
                    raw,
                    json,
                    trace,
                },
                InputMode::Stdin,
            )
            .await
        }
        Commands::Scenario {
            ws_url,
            session_id,
            resume_offset,
            state_file,
            no_resume,
            raw,
            json,
            trace,
            scenario_file,
            step_ms,
        } => {
            let lines = match load_scenario_lines(&scenario_file) {
                Ok(v) => v,
                Err(err) => {
                    eprintln!(
                        "failed to load scenario file {}: {err}",
                        scenario_file.display()
                    );
                    std::process::exit(1);
                }
            };

            run_connect(
                ConnectConfig {
                    ws_url,
                    session_id,
                    resume_offset,
                    state_file,
                    no_resume,
                    raw,
                    json,
                    trace,
                },
                InputMode::Scenario { lines, step_ms },
            )
            .await
        }
    };

    if let Err(err) = result {
        eprintln!("moo-cli error: {err}");
        std::process::exit(1);
    }
}

async fn run_connect(
    config: ConnectConfig,
    input_mode: InputMode,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut state = resolve_initial_state(
        config.session_id.clone(),
        config.resume_offset,
        config.state_file.as_deref(),
    )?;

    save_state_if_enabled(config.state_file.as_deref(), &state)?;

    let (tx, mut rx) = mpsc::unbounded_channel::<Outbound>();
    match input_mode {
        InputMode::Stdin => spawn_stdin_task(tx),
        InputMode::Scenario { lines, step_ms } => spawn_scenario_task(tx, lines, step_ms),
    }

    loop {
        let control = run_single_connection(&config, &mut state, &mut rx).await?;
        save_state_if_enabled(config.state_file.as_deref(), &state)?;
        match control {
            LoopControl::Exit => break,
            LoopControl::Reconnect => continue,
        }
    }

    Ok(())
}

async fn run_single_connection(
    config: &ConnectConfig,
    state: &mut SessionState,
    rx: &mut mpsc::UnboundedReceiver<Outbound>,
) -> Result<LoopControl, Box<dyn std::error::Error>> {
    if config.trace {
        println!(
            "trace: connect ws_url={} session_id={} resume_offset={}",
            config.ws_url, state.session_id, state.current_offset
        );
    }

    let (stream, _) = connect_async(&config.ws_url).await?;
    println!("connected: {}", config.ws_url);

    let (mut write, mut read) = stream.split();

    write
        .send(Message::Text(
            format!("HELLO {}\n", state.session_id).into(),
        ))
        .await?;
    if config.trace {
        println!("trace: sent HELLO {}", state.session_id);
    }

    if !config.no_resume && state.current_offset > 0 {
        write
            .send(Message::Text(
                format!("RESUME {}\n", state.current_offset).into(),
            ))
            .await?;
        if config.trace {
            println!("trace: sent RESUME {}", state.current_offset);
        }
    }

    let mut receive_buffer: Vec<u8> = Vec::new();

    loop {
        tokio::select! {
            maybe_out = rx.recv() => {
                match maybe_out {
                    Some(Outbound::RawLine(line)) => {
                        match parse_command(&line) {
                            Command::Send(text) => {
                                if config.trace {
                                    println!("trace: sent SEND {}", text);
                                }
                                write.send(Message::Text(format!("SEND {text}\n").into())).await?;
                            }
                            Command::Ping => {
                                if config.trace {
                                    println!("trace: sent PING");
                                }
                                write.send(Message::Text("PING\n".into())).await?;
                            }
                            Command::Offset => {
                                println!("offset={}", state.current_offset);
                            }
                            Command::Wait(wait_ms) => {
                                if config.trace {
                                    println!("trace: wait {wait_ms}ms");
                                }
                                sleep(Duration::from_millis(wait_ms)).await;
                            }
                            Command::Resume(new_offset) => {
                                state.current_offset = new_offset;
                                println!("resume_offset={new_offset}");
                                save_state_if_enabled(config.state_file.as_deref(), state)?;
                            }
                            Command::Reconnect(maybe_offset) => {
                                if let Some(new_offset) = maybe_offset {
                                    state.current_offset = new_offset;
                                    println!("resume_offset={new_offset}");
                                    save_state_if_enabled(config.state_file.as_deref(), state)?;
                                }
                                println!("reconnecting...");
                                if config.trace {
                                    println!("trace: reconnect requested");
                                }
                                return Ok(LoopControl::Reconnect);
                            }
                            Command::Quit => {
                                if config.trace {
                                    println!("trace: quit requested");
                                }
                                return Ok(LoopControl::Exit);
                            }
                            Command::Unknown(raw) => {
                                println!("unknown command: {raw}");
                            }
                        }
                    }
                    Some(Outbound::Quit) | None => {
                        if config.trace {
                            println!("trace: input ended");
                        }
                        return Ok(LoopControl::Exit);
                    }
                }
            }
            maybe_msg = read.next() => {
                match maybe_msg {
                    Some(Ok(Message::Text(text))) => {
                        for line in text.split('\n') {
                            if line.is_empty() {
                                continue;
                            }
                            if config.raw {
                                println!("raw-control: {line}");
                            }
                            if line == "PONG" {
                                if config.trace {
                                    println!("trace: recv PONG");
                                }
                                println!("pong");
                            } else if let Some(rest) = line.strip_prefix("WELCOME ") {
                                if config.trace {
                                    println!("trace: recv WELCOME {rest}");
                                }
                                println!("welcome: {rest}");
                            } else {
                                if config.trace {
                                    println!("trace: recv control {line}");
                                }
                                println!("control: {line}");
                            }
                        }
                    }
                    Some(Ok(Message::Binary(bin))) => {
                        if !bin.starts_with(b"DATA ") {
                            if config.raw {
                                println!("raw-binary: {} bytes", bin.len());
                            }
                            continue;
                        }
                        let payload = &bin[5..];
                        if config.raw {
                            println!("raw-data-bytes: {}", payload.len());
                        }
                        if config.trace {
                            println!(
                                "trace: recv DATA chunk={} offset_before={}",
                                payload.len(),
                                state.current_offset
                            );
                        }
                        receive_buffer.extend_from_slice(payload);

                        while let Some(newline_idx) = receive_buffer.iter().position(|b| *b == b'\n') {
                            let line_bytes: Vec<u8> = receive_buffer.drain(..=newline_idx).collect();
                            let text_bytes = &line_bytes[..line_bytes.len() - 1];
                            state.current_offset += line_bytes.len() as u64;
                            save_state_if_enabled(config.state_file.as_deref(), state)?;

                            if let Ok(raw_line) = std::str::from_utf8(text_bytes) {
                                let line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
                                if config.trace {
                                    println!("trace: next_offset={}", state.current_offset);
                                }
                                let event = classify_line(line, state.current_offset);
                                if config.json {
                                    println!("{}", serde_json::to_string(&event)?);
                                } else {
                                    println!("event: {:?}", event);
                                }
                            }
                        }
                    }
                    Some(Ok(Message::Close(_))) => {
                        if config.trace {
                            println!("trace: server sent close");
                        }
                        println!("server closed connection");
                        return Ok(LoopControl::Exit);
                    }
                    Some(Ok(_)) => {}
                    Some(Err(err)) => return Err(Box::new(err)),
                    None => {
                        if config.trace {
                            println!("trace: websocket stream ended");
                        }
                        println!("connection ended");
                        return Ok(LoopControl::Exit);
                    }
                }
            }
        }
    }
}

fn spawn_stdin_task(tx: mpsc::UnboundedSender<Outbound>) {
    tokio::spawn(async move {
        let stdin = io::stdin();
        let mut reader = BufReader::new(stdin).lines();
        println!(
            "interactive mode: type text to SEND, /ping, /offset, /wait <ms>, /reconnect [offset], /quit"
        );

        loop {
            match reader.next_line().await {
                Ok(Some(line)) => {
                    if tx.send(Outbound::RawLine(line)).is_err() {
                        break;
                    }
                }
                Ok(None) => {
                    let _ = tx.send(Outbound::Quit);
                    break;
                }
                Err(_) => {
                    let _ = tx.send(Outbound::Quit);
                    break;
                }
            }
        }
    });
}

fn spawn_scenario_task(tx: mpsc::UnboundedSender<Outbound>, lines: Vec<String>, step_ms: u64) {
    tokio::spawn(async move {
        for line in lines {
            if tx.send(Outbound::RawLine(line)).is_err() {
                return;
            }
            sleep(Duration::from_millis(step_ms)).await;
        }
        let _ = tx.send(Outbound::Quit);
    });
}

fn load_scenario_lines(path: &Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let input = fs::read_to_string(path)?;
    let mut out = Vec::new();
    for raw in input.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        out.push(line.to_string());
    }
    Ok(out)
}

fn default_session_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("moo-cli-{nanos}")
}

fn parse_command(line: &str) -> Command {
    if !line.starts_with('/') {
        return Command::Send(line.to_string());
    }
    if line == "/ping" {
        return Command::Ping;
    }
    if line == "/offset" {
        return Command::Offset;
    }
    if line == "/quit" {
        return Command::Quit;
    }
    if let Some(arg) = line.strip_prefix("/wait ") {
        return match arg.trim().parse::<u64>() {
            Ok(wait_ms) => Command::Wait(wait_ms),
            Err(_) => Command::Unknown(line.to_string()),
        };
    }
    if let Some(arg) = line.strip_prefix("/resume ") {
        return match arg.trim().parse::<u64>() {
            Ok(offset) => Command::Resume(offset),
            Err(_) => Command::Unknown(line.to_string()),
        };
    }
    if line == "/reconnect" {
        return Command::Reconnect(None);
    }
    if let Some(arg) = line.strip_prefix("/reconnect ") {
        return match arg.trim().parse::<u64>() {
            Ok(offset) => Command::Reconnect(Some(offset)),
            Err(_) => Command::Unknown(line.to_string()),
        };
    }
    Command::Unknown(line.to_string())
}

fn resolve_initial_state(
    session_id_arg: Option<String>,
    resume_offset_arg: Option<u64>,
    state_file: Option<&Path>,
) -> Result<SessionState, Box<dyn std::error::Error>> {
    let loaded = load_state_if_enabled(state_file)?;
    let session_id = session_id_arg
        .or_else(|| loaded.as_ref().map(|s| s.session_id.clone()))
        .unwrap_or_else(default_session_id);
    let current_offset = resume_offset_arg
        .or_else(|| loaded.as_ref().map(|s| s.last_offset))
        .unwrap_or(0);
    Ok(SessionState {
        session_id,
        current_offset,
    })
}

fn load_state_if_enabled(
    state_file: Option<&Path>,
) -> Result<Option<PersistedState>, Box<dyn std::error::Error>> {
    let Some(path) = state_file else {
        return Ok(None);
    };
    if !path.exists() {
        return Ok(None);
    }
    let raw = fs::read_to_string(path)?;
    if raw.trim().is_empty() {
        return Ok(None);
    }
    let state = serde_json::from_str::<PersistedState>(&raw)?;
    Ok(Some(state))
}

fn save_state_if_enabled(
    state_file: Option<&Path>,
    state: &SessionState,
) -> Result<(), Box<dyn std::error::Error>> {
    let Some(path) = state_file else {
        return Ok(());
    };
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    let payload = PersistedState {
        session_id: state.session_id.clone(),
        last_offset: state.current_offset,
    };
    let json = serde_json::to_string_pretty(&payload)?;
    fs::write(path, json)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        load_scenario_lines, load_state_if_enabled, parse_command, save_state_if_enabled, Command,
        SessionState,
    };
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_path(prefix: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!("{prefix}-{nanos}.tmp"))
    }

    #[test]
    fn parses_reconnect_with_offset() {
        match parse_command("/reconnect 42") {
            Command::Reconnect(Some(42)) => {}
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn parses_resume_with_offset() {
        match parse_command("/resume 123") {
            Command::Resume(123) => {}
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn parses_wait_with_millis() {
        match parse_command("/wait 250") {
            Command::Wait(250) => {}
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn state_file_round_trip() {
        let path = unique_path("moo-cli-state");
        let state = SessionState {
            session_id: "test-session".to_string(),
            current_offset: 999,
        };

        save_state_if_enabled(Some(path.as_path()), &state).expect("save state");
        let loaded = load_state_if_enabled(Some(path.as_path()))
            .expect("load state")
            .expect("state exists");

        assert_eq!(loaded.session_id, "test-session");
        assert_eq!(loaded.last_offset, 999);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn scenario_loader_skips_comments_and_blank_lines() {
        let path = unique_path("moo-cli-scenario");
        fs::write(&path, "# comment\n\nlook\n/reconnect\n").expect("write scenario");

        let lines = load_scenario_lines(&path).expect("load scenario");
        assert_eq!(lines, vec!["look".to_string(), "/reconnect".to_string()]);

        let _ = fs::remove_file(path);
    }
}
