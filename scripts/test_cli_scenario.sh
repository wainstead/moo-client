#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_LOG="$(mktemp)"
PROXY_LOG="$(mktemp)"
STATE_FILE="$(mktemp)"
SCENARIO_FILE="${ROOT_DIR}/scripts/scenarios/resume_scenario.txt"
TEST_PORT="${MOO_PROXY_TEST_PORT:-19000}"

cleanup() {
  if [[ -n "${PROXY_PID:-}" ]]; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
    wait "$PROXY_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$CLI_LOG" "$PROXY_LOG" "$STATE_FILE"
}
trap cleanup EXIT

pick_free_port() {
  local p
  for p in $(seq 19000 19100); do
    if ! nc -z 127.0.0.1 "$p" >/dev/null 2>&1; then
      TEST_PORT="$p"
      return 0
    fi
  done
  echo "[FAIL] could not find a free localhost port for proxy test"
  exit 1
}

cd "$ROOT_DIR"

echo "[INFO] Ensuring local LambdaMOO is running"
echo "[INFO] Resetting local LambdaMOO state"
./scripts/run_local_moo.sh reset >/dev/null || true
./scripts/run_local_moo.sh up >/dev/null
./scripts/run_local_moo.sh bootstrap >/dev/null

pick_free_port
echo "[INFO] Using proxy test port ${TEST_PORT}"
echo "[INFO] Starting proxy on :${TEST_PORT}"
LISTEN_ADDR="127.0.0.1:${TEST_PORT}" ./scripts/run_proxy.sh >"$PROXY_LOG" 2>&1 &
PROXY_PID=$!
sleep 1

echo "[INFO] Running moo-cli scenario"
(
  cd core
  cargo run --quiet --bin moo-cli -- scenario \
    --ws-url "ws://127.0.0.1:${TEST_PORT}/ws" \
    --scenario-file "$SCENARIO_FILE" \
    --state-file "$STATE_FILE" \
    --json \
    --trace \
    --step-ms 120
) >"$CLI_LOG"

if ! grep -q '^welcome:' "$CLI_LOG"; then
  echo "[FAIL] scenario did not receive WELCOME"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  echo "--- proxy log ---"
  cat "$PROXY_LOG"
  exit 1
fi

if ! grep -q '^reconnecting\.\.\.' "$CLI_LOG"; then
  echo "[FAIL] scenario did not execute reconnect"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

if ! grep -q '^trace: sent HELLO ' "$CLI_LOG"; then
  echo "[FAIL] scenario missing trace output"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

if ! grep -q '^pong$' "$CLI_LOG"; then
  echo "[FAIL] scenario did not receive PONG"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

if [[ "$(grep -c '^offset=' "$CLI_LOG")" -lt 2 ]]; then
  echo "[FAIL] scenario did not report offset multiple times"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

if [[ ! -s "$STATE_FILE" ]]; then
  echo "[FAIL] scenario did not write state file"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

echo "[PASS] moo-cli scenario smoke test succeeded"
