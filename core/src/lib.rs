use once_cell::sync::Lazy;
use regex::Regex;
use serde::{Deserialize, Serialize};

static CHAT_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^([^:]+):\s+(.*)$").expect("chat regex"));
static ARRIVE_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^(.+) has arrived\.$").expect("arrive regex"));
static LEAVE_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^(.+) has left\.$").expect("leave regex"));

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Event {
    Chat {
        speaker: String,
        message: String,
        offset: u64,
    },
    Arrive {
        who: String,
        offset: u64,
    },
    Leave {
        who: String,
        offset: u64,
    },
    System {
        text: String,
        offset: u64,
    },
}

pub fn classify_line(line: &str, offset: u64) -> Event {
    if let Some(caps) = CHAT_RE.captures(line) {
        return Event::Chat {
            speaker: caps[1].trim().to_string(),
            message: caps[2].to_string(),
            offset,
        };
    }

    if let Some(caps) = ARRIVE_RE.captures(line) {
        return Event::Arrive {
            who: caps[1].trim().to_string(),
            offset,
        };
    }

    if let Some(caps) = LEAVE_RE.captures(line) {
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
