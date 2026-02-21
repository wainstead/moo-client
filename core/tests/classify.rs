use moo_core::{classify_line, Event};

#[test]
fn classifies_chat() {
    let got = classify_line("Frog: hello there", 12);
    assert_eq!(
        got,
        Event::Chat {
            speaker: "Frog".to_string(),
            message: "hello there".to_string(),
            offset: 12
        }
    );
}

#[test]
fn classifies_arrive() {
    let got = classify_line("Wizard has arrived.", 21);
    assert_eq!(
        got,
        Event::Arrive {
            who: "Wizard".to_string(),
            offset: 21
        }
    );
}

#[test]
fn classifies_leave() {
    let got = classify_line("Guest has left.", 33);
    assert_eq!(
        got,
        Event::Leave {
            who: "Guest".to_string(),
            offset: 33
        }
    );
}

#[test]
fn classifies_system() {
    let got = classify_line("*** Connected to LambdaMOO ***", 5);
    assert_eq!(
        got,
        Event::System {
            text: "*** Connected to LambdaMOO ***".to_string(),
            offset: 5
        }
    );
}
