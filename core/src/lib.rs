use regex::Regex;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Chat { speaker: String, message: String },
    Arrive { who: String },
    Leave { who: String },
    System { text: String },
}

pub fn classify_line(line: &str) -> Event {
    let chat = Regex::new(r"^([^:]+):\s+(.*)$").expect("chat regex");
    let arrive = Regex::new(r"^(.+) has arrived\.$").expect("arrive regex");
    let leave = Regex::new(r"^(.+) has left\.$").expect("leave regex");

    if let Some(caps) = chat.captures(line) {
        return Event::Chat {
            speaker: caps[1].trim().to_string(),
            message: caps[2].to_string(),
        };
    }

    if let Some(caps) = arrive.captures(line) {
        return Event::Arrive {
            who: caps[1].trim().to_string(),
        };
    }

    if let Some(caps) = leave.captures(line) {
        return Event::Leave {
            who: caps[1].trim().to_string(),
        };
    }

    Event::System {
        text: line.to_string(),
    }
}
