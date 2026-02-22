#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

printf "[INFO] Coverage summary\n"
printf "\n"
printf "%-12s %-10s %s\n" "Component" "Status" "Details"
printf "%-12s %-10s %s\n" "---------" "------" "-------"

# Go coverage (proxy)
GO_COV="$TMP_DIR/proxy.cover.out"
if (
  cd "$ROOT_DIR/proxy"
  go test ./... -coverprofile="$GO_COV" -covermode=atomic >/dev/null
); then
  go_total="$(
    cd "$ROOT_DIR/proxy"
    go tool cover -func="$GO_COV" | awk '/^total:/ {print $3}'
  )"
  printf "%-12s %-10s %s\n" "proxy(go)" "ok" "total=${go_total}"
else
  printf "%-12s %-10s %s\n" "proxy(go)" "fail" "go coverage failed"
  exit 1
fi

# Rust coverage (core) via cargo-llvm-cov if available.
if command -v cargo-llvm-cov >/dev/null 2>&1; then
  RUST_LOG="$TMP_DIR/rust_cov.log"
  if (
    cd "$ROOT_DIR/core"
    cargo llvm-cov --summary-only >"$RUST_LOG"
  ); then
    rust_total="$(awk '/^TOTAL/ {print $(NF-1)}' "$RUST_LOG" | tail -n1)"
    if [[ -z "$rust_total" ]]; then
      rust_total="see core llvm-cov output"
    fi
    printf "%-12s %-10s %s\n" "core(rust)" "ok" "${rust_total}"
  else
    printf "%-12s %-10s %s\n" "core(rust)" "fail" "cargo llvm-cov failed"
    exit 1
  fi
else
  printf "%-12s %-10s %s\n" "core(rust)" "skip" "install cargo-llvm-cov for line coverage"
fi

# Swift coverage (ios-app)
SWIFT_LOG="$TMP_DIR/swift_test_cov.log"
if (
  cd "$ROOT_DIR/ios-app"
  swift test --enable-code-coverage >"$SWIFT_LOG" 2>&1
); then
  codecov_json="$(
    cd "$ROOT_DIR/ios-app"
    swift test --show-codecov-path 2>/dev/null || true
  )"
  if [[ -n "$codecov_json" && -f "$codecov_json" ]]; then
    swift_total="$(
      sed -n 's/.*"totals":.*"lines":{"count":[0-9]*,"covered":[0-9]*,"percent":\([0-9.]*\).*/\1/p' "$codecov_json" | head -n1
    )"
    if [[ -n "$swift_total" ]]; then
      printf "%-12s %-10s %s\n" "ios(swift)" "ok" "lines=${swift_total}%"
    else
      printf "%-12s %-10s %s\n" "ios(swift)" "ok" "coverage collected (could not parse totals)"
    fi
  else
    printf "%-12s %-10s %s\n" "ios(swift)" "ok" "coverage collected (codecov path unavailable)"
  fi
else
  printf "%-12s %-10s %s\n" "ios(swift)" "fail" "swift coverage failed"
  exit 1
fi

printf "\n"
printf "[INFO] Coverage run complete\n"
