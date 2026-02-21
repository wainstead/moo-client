use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Event {
    Chat { speaker: String, message: String, offset: u64 },
    Arrive { who: String, offset: u64 },
    Leave { who: String, offset: u64 },
    System { text: String, offset: u64 },
}

pub fn classify_line(line: &str, offset: u64) -> Event {
    let chat = Regex::new(r"^([^:]+):\s+(.*)$").expect("chat regex");
    let arrive = Regex::new(r"^(.+) has arrived\.$").expect("arrive regex");
    let leave = Regex::new(r"^(.+) has left\.$").expect("leave regex");

    if let Some(caps) = chat.captures(line) {
        return Event::Chat {
            speaker: caps[1].trim().to_string(),
            message: caps[2].to_string(),
            offset,
        };
    }

    if let Some(caps) = arrive.captures(line) {
        return Event::Arrive {
            who: caps[1].trim().to_string(),
            offset,
        };
    }

    if let Some(caps) = leave.captures(line) {
        return Event::Leave {
            who: caps[1].trim().to_string(),
            offset,
        };
    }

    Event::System {
        text: line.to_string(),
        offset,
    }
}
