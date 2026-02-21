use std::io::{self, BufRead};

use moo_core::classify_line;

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        match line {
            Ok(text) => {
                let (offset, raw) = parse_input_line(&text);
                let event = classify_line(raw, offset);
                match serde_json::to_string(&event) {
                    Ok(json) => println!("{json}"),
                    Err(err) => {
                        eprintln!("json encode error: {err}");
                        std::process::exit(1);
                    }
                }
            }
            Err(err) => {
                eprintln!("stdin read error: {err}");
                std::process::exit(1);
            }
        }
    }
}

fn parse_input_line(line: &str) -> (u64, &str) {
    if let Some((offset, text)) = line.split_once('\t') {
        if let Ok(v) = offset.parse::<u64>() {
            return (v, text);
        }
    }
    (0, line)
}
