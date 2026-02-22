use std::time::{SystemTime, UNIX_EPOCH};

use clap::{Parser, Subcommand};
use futures_util::{SinkExt, StreamExt};
use moo_core::classify_line;
use tokio::io::{self, AsyncBufReadExt, BufReader};
use tokio::sync::mpsc;
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

        #[arg(long, default_value_t = 0)]
        resume_offset: u64,

        #[arg(long)]
        no_resume: bool,

        #[arg(long)]
        raw: bool,

        #[arg(long)]
        json: bool,

        #[arg(long)]
        trace: bool,
    },
}

#[derive(Debug)]
enum Outbound {
    RawLine(String),
    Quit,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Connect {
            ws_url,
            session_id,
            resume_offset,
            no_resume,
            raw,
            json,
            trace,
        } => {
            if let Err(err) = run_connect(
                ws_url,
                session_id.unwrap_or_else(default_session_id),
                resume_offset,
                no_resume,
                raw,
                json,
                trace,
            )
            .await
            {
                eprintln!("moo-cli error: {err}");
                std::process::exit(1);
            }
        }
    }
}

async fn run_connect(
    ws_url: String,
    session_id: String,
    mut current_offset: u64,
    no_resume: bool,
    raw: bool,
    json: bool,
    trace: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let (stream, _) = connect_async(&ws_url).await?;
    println!("connected: {ws_url}");

    let (mut write, mut read) = stream.split();

    write
        .send(Message::Text(format!("HELLO {session_id}\n").into()))
        .await?;
    if !no_resume && current_offset > 0 {
        write
            .send(Message::Text(format!("RESUME {current_offset}\n").into()))
            .await?;
    }

    let (tx, mut rx) = mpsc::unbounded_channel::<Outbound>();
    spawn_stdin_task(tx);

    let mut receive_buffer: Vec<u8> = Vec::new();

    loop {
        tokio::select! {
            maybe_out = rx.recv() => {
                match maybe_out {
                    Some(Outbound::RawLine(line)) => {
                        if line.starts_with('/') {
                            match line.as_str() {
                                "/ping" => {
                                    write.send(Message::Text("PING\n".into())).await?;
                                }
                                "/offset" => {
                                    println!("offset={current_offset}");
                                }
                                "/quit" => {
                                    break;
                                }
                                _ => {
                                    println!("unknown command: {line}");
                                }
                            }
                        } else {
                            write.send(Message::Text(format!("SEND {line}\n").into())).await?;
                        }
                    }
                    Some(Outbound::Quit) | None => {
                        break;
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
                            if raw {
                                println!("raw-control: {line}");
                            }
                            if line == "PONG" {
                                println!("pong");
                            } else if let Some(rest) = line.strip_prefix("WELCOME ") {
                                println!("welcome: {rest}");
                            } else {
                                println!("control: {line}");
                            }
                        }
                    }
                    Some(Ok(Message::Binary(bin))) => {
                        if !bin.starts_with(b"DATA ") {
                            if raw {
                                println!("raw-binary: {} bytes", bin.len());
                            }
                            continue;
                        }
                        let payload = &bin[5..];
                        if raw {
                            println!("raw-data-bytes: {}", payload.len());
                        }
                        receive_buffer.extend_from_slice(payload);

                        while let Some(newline_idx) = receive_buffer.iter().position(|b| *b == b'\n') {
                            let line_bytes: Vec<u8> = receive_buffer.drain(..=newline_idx).collect();
                            let text_bytes = &line_bytes[..line_bytes.len()-1];
                            current_offset += line_bytes.len() as u64;

                            if let Ok(raw_line) = std::str::from_utf8(text_bytes) {
                                let line = raw_line.strip_suffix('\r').unwrap_or(raw_line);
                                if trace {
                                    println!("trace: next_offset={current_offset}");
                                }
                                let event = classify_line(line, current_offset);
                                if json {
                                    println!("{}", serde_json::to_string(&event)?);
                                } else {
                                    println!("event: {:?}", event);
                                }
                            }
                        }
                    }
                    Some(Ok(Message::Close(_))) => {
                        println!("server closed connection");
                        break;
                    }
                    Some(Ok(_)) => {}
                    Some(Err(err)) => return Err(Box::new(err)),
                    None => {
                        println!("connection ended");
                        break;
                    }
                }
            }
        }
    }

    Ok(())
}

fn spawn_stdin_task(tx: mpsc::UnboundedSender<Outbound>) {
    tokio::spawn(async move {
        let stdin = io::stdin();
        let mut reader = BufReader::new(stdin).lines();
        println!("interactive mode: type text to SEND, /ping, /offset, /quit");

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

fn default_session_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("moo-cli-{nanos}")
}
