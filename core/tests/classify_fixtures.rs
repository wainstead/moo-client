use std::fs;
use std::path::PathBuf;

use moo_core::{classify_line, Event};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Fixture {
    line: String,
    offset: u64,
    expected: Event,
}

#[test]
fn classify_matches_shared_fixtures() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("core has parent")
        .to_path_buf();
    let path = root.join("fixtures/classifier_fixtures.jsonl");
    let input = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("failed to read fixtures {}: {err}", path.display()));

    for (idx, raw) in input.lines().enumerate() {
        if raw.trim().is_empty() {
            continue;
        }
        let fixture: Fixture = serde_json::from_str(raw)
            .unwrap_or_else(|err| panic!("invalid fixture JSON at line {}: {err}", idx + 1));
        let got = classify_line(&fixture.line, fixture.offset);
        assert_eq!(
            got,
            fixture.expected,
            "fixture mismatch at line {} for input {:?}",
            idx + 1,
            fixture.line
        );
    }
}
