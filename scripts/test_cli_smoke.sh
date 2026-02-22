#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_LOG="$(mktemp)"
PROXY_LOG="$(mktemp)"
TEST_PORT="${MOO_PROXY_TEST_PORT:-19000}"

cleanup() {
  if [[ -n "${PROXY_PID:-}" ]]; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
    wait "$PROXY_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$CLI_LOG" "$PROXY_LOG"
}
trap cleanup EXIT

cd "$ROOT_DIR"

echo "[INFO] Ensuring local LambdaMOO is running"
./scripts/run_local_moo.sh up >/dev/null
./scripts/run_local_moo.sh bootstrap >/dev/null

echo "[INFO] Starting proxy on :${TEST_PORT}"
LISTEN_ADDR="127.0.0.1:${TEST_PORT}" ./scripts/run_proxy.sh >"$PROXY_LOG" 2>&1 &
PROXY_PID=$!
sleep 1

echo "[INFO] Running moo-cli scripted session"
printf 'connect wizard wizardtest\nlook\n/ping\n/offset\n/quit\n' \
  | (cd core && cargo run --quiet --bin moo-cli -- connect --ws-url "ws://127.0.0.1:${TEST_PORT}/ws" --json) \
  >"$CLI_LOG"

if ! grep -q '^welcome:' "$CLI_LOG"; then
  echo "[FAIL] moo-cli did not receive WELCOME"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  echo "--- proxy log ---"
  cat "$PROXY_LOG"
  exit 1
fi

if ! grep -q '"Welcome to the LambdaCore database."' "$CLI_LOG"; then
  echo "[FAIL] moo-cli did not receive LambdaMOO welcome text"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  echo "--- proxy log ---"
  cat "$PROXY_LOG"
  exit 1
fi

if ! grep -q '^offset=' "$CLI_LOG"; then
  echo "[FAIL] moo-cli did not report offset"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

echo "[PASS] moo-cli smoke test succeeded"
