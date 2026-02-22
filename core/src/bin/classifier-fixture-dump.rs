use std::fs;
use std::path::PathBuf;

use clap::Parser;
use moo_core::{classify_line, Event};
use serde::Deserialize;

#[derive(Parser, Debug)]
#[command(name = "classifier-fixture-dump")]
#[command(about = "Emit normalized classifier output for shared fixtures")]
struct Cli {
    #[arg(default_value = "../fixtures/classifier_fixtures.jsonl")]
    fixture_file: PathBuf,
}

#[derive(Debug, Deserialize)]
struct Fixture {
    line: String,
    offset: u64,
}

fn main() {
    let cli = Cli::parse();
    let input = match fs::read_to_string(&cli.fixture_file) {
        Ok(v) => v,
        Err(err) => {
            eprintln!(
                "failed to read fixture file {}: {err}",
                cli.fixture_file.display()
            );
            std::process::exit(1);
        }
    };

    for (idx, raw) in input.lines().enumerate() {
        if raw.trim().is_empty() {
            continue;
        }
        let fixture: Fixture = match serde_json::from_str(raw) {
            Ok(v) => v,
            Err(err) => {
                eprintln!("invalid fixture JSON at line {}: {err}", idx + 1);
                std::process::exit(1);
            }
        };

        let event = classify_line(&fixture.line, fixture.offset);
        println!("{}", normalize(idx, event));
    }
}

fn normalize(idx: usize, event: Event) -> String {
    match event {
        Event::Chat {
            speaker,
            message,
            offset,
        } => format!("{idx}|chat|{offset}|{speaker}|{message}"),
        Event::Arrive { who, offset } => format!("{idx}|arrive|{offset}|{who}"),
        Event::Leave { who, offset } => format!("{idx}|leave|{offset}|{who}"),
        Event::System { text, offset } => format!("{idx}|system|{offset}|{text}"),
    }
}
