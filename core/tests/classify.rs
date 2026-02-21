use moo_core::{classify_line, Event};

#[test]
fn classifies_chat() {
    let got = classify_line("Frog: hello there");
    assert_eq!(
        got,
        Event::Chat {
            speaker: "Frog".to_string(),
            message: "hello there".to_string()
        }
    );
}

#[test]
fn classifies_arrive() {
    let got = classify_line("Wizard has arrived.");
    assert_eq!(
        got,
        Event::Arrive {
            who: "Wizard".to_string()
        }
    );
}

#[test]
fn classifies_leave() {
    let got = classify_line("Guest has left.");
    assert_eq!(
        got,
        Event::Leave {
            who: "Guest".to_string()
        }
    );
}

#[test]
fn classifies_system() {
    let got = classify_line("*** Connected to LambdaMOO ***");
    assert_eq!(
        got,
        Event::System {
            text: "*** Connected to LambdaMOO ***".to_string()
        }
    );
}
