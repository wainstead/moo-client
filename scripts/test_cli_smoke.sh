#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_LOG="$(mktemp)"
PROXY_LOG="$(mktemp)"
STATE_FILE="$(mktemp)"
TEST_PORT="${MOO_PROXY_TEST_PORT:-19000}"

kill_port_listener() {
  local port="$1"
  local pids

  if [[ -z "$port" ]]; then
    return 0
  fi

  pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    kill $pids >/dev/null 2>&1 || true
    sleep 0.2
    pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
      kill -9 $pids >/dev/null 2>&1 || true
    fi
  fi
}

cleanup() {
  if [[ -n "${PROXY_PID:-}" ]]; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
    wait "$PROXY_PID" >/dev/null 2>&1 || true
  fi
  kill_port_listener "$TEST_PORT"
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

echo "[INFO] Running moo-cli scripted session"
{
  printf 'connect wizard wizardtest\n'
  sleep 1
  printf 'look\n'
  sleep 1
  printf '/ping\n'
  sleep 1
  printf '/offset\n'
  sleep 1
  printf '/reconnect\n'
  sleep 1
  printf '/offset\n'
  sleep 1
  printf '/quit\n'
} | (cd core && cargo run --quiet --bin moo-cli -- connect --ws-url "ws://127.0.0.1:${TEST_PORT}/ws" --state-file "$STATE_FILE" --json) \
  >"$CLI_LOG" || true

if ! grep -q '^welcome:' "$CLI_LOG"; then
  echo "[FAIL] moo-cli did not receive WELCOME"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  echo "--- proxy log ---"
  cat "$PROXY_LOG"
  exit 1
fi

if ! grep -q '^reconnecting\.\.\.' "$CLI_LOG"; then
  echo "[FAIL] moo-cli reconnect command did not execute"
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

if [[ ! -s "$STATE_FILE" ]]; then
  echo "[FAIL] state file was not written"
  echo "--- cli log ---"
  cat "$CLI_LOG"
  exit 1
fi

echo "[PASS] moo-cli smoke test succeeded"
