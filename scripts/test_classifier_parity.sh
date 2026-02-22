#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_FILE="${ROOT_DIR}/fixtures/classifier_fixtures.jsonl"
RUST_OUT="$(mktemp)"
SWIFT_OUT="$(mktemp)"

cleanup() {
  rm -f "$RUST_OUT" "$SWIFT_OUT"
}
trap cleanup EXIT

echo "[INFO] Running Rust fixture test"
(
  cd "$ROOT_DIR/core"
  cargo test --test classify_fixtures
) >/dev/null

echo "[INFO] Running Swift fixture test"
(
  cd "$ROOT_DIR/ios-app"
  swift test --filter CoreEventFixtureTests
) >/dev/null

echo "[INFO] Collecting normalized outputs"
(
  cd "$ROOT_DIR/core"
  cargo run --quiet --bin classifier-fixture-dump -- "$FIXTURE_FILE"
) >"$RUST_OUT"

(
  cd "$ROOT_DIR/ios-app"
  swift run MooIOSCoreFixtureRunner "$FIXTURE_FILE"
) >"$SWIFT_OUT"

if ! diff -u "$RUST_OUT" "$SWIFT_OUT" >/dev/null; then
  echo "[FAIL] classifier outputs diverged"
  echo "--- rust ---"
  cat "$RUST_OUT"
  echo "--- swift ---"
  cat "$SWIFT_OUT"
  exit 1
fi

echo "[PASS] classifier parity succeeded"
