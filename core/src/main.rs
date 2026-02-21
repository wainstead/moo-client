use std::io::{self, BufRead};

use moo_core::{classify_line, Event};

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        match line {
            Ok(text) => {
                let event = classify_line(&text);
                println!("{}", render_event(&event));
            }
            Err(err) => {
                eprintln!("stdin read error: {err}");
                std::process::exit(1);
            }
        }
    }
}

fn render_event(event: &Event) -> String {
    match event {
        Event::Chat { speaker, message } => {
            format!("Chat speaker={speaker:?} message={message:?}")
        }
        Event::Arrive { who } => format!("Arrive who={who:?}"),
        Event::Leave { who } => format!("Leave who={who:?}"),
        Event::System { text } => format!("System text={text:?}"),
    }
}
