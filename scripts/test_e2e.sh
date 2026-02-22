#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH="/opt/homebrew/bin:$PATH"

PROXY_LOG="$(mktemp -t moo-proxy-log.XXXXXX)"
CLIENT_LOG="$(mktemp -t moo-client-log.XXXXXX)"
CLIENT_FIFO="$(mktemp -u -t moo-client-fifo.XXXXXX)"
TEST_PORT=""
PROXY_PID=""
CLIENT_PID=""

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
  set +e
  if [[ -n "$CLIENT_PID" ]]; then
    kill "$CLIENT_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$PROXY_PID" ]]; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
  fi
  kill_port_listener "$TEST_PORT"
  rm -f "$CLIENT_FIFO" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $1"
  echo "--- proxy log ---"
  cat "$PROXY_LOG" || true
  echo "--- client log ---"
  cat "$CLIENT_LOG" || true
  exit 1
}

ensure_client_alive() {
  if ! kill -0 "$CLIENT_PID" >/dev/null 2>&1; then
    fail "test client exited unexpectedly"
  fi
}

send_line() {
  local line="$1"
  ensure_client_alive
  if ! printf '%s\n' "$line" >&3; then
    fail "failed to write to test client"
  fi
}

pick_free_port() {
  local p
  for p in $(seq 19000 19100); do
    if ! nc -z 127.0.0.1 "$p" >/dev/null 2>&1; then
      TEST_PORT="$p"
      return 0
    fi
  done
  fail "could not find a free localhost port for proxy test"
}

expect_pattern() {
  local pattern="$1"
  local timeout="${2:-20}"
  local deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if grep -qF "$pattern" "$CLIENT_LOG"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

echo "[INFO] Ensuring local LambdaMOO is running"
echo "[INFO] Resetting local LambdaMOO state"
"$ROOT_DIR/scripts/run_local_moo.sh" reset >/dev/null || true
"$ROOT_DIR/scripts/run_local_moo.sh" up >/dev/null
"$ROOT_DIR/scripts/run_local_moo.sh" bootstrap >/dev/null

echo "[INFO] Starting proxy"
pick_free_port
echo "[INFO] Using proxy test port $TEST_PORT"
(
  cd "$ROOT_DIR"
  LISTEN_ADDR="127.0.0.1:$TEST_PORT" GOCACHE=/tmp/go-build ./scripts/run_proxy.sh
) >"$PROXY_LOG" 2>&1 &
PROXY_PID=$!

for _ in $(seq 1 30); do
  if nc -z 127.0.0.1 "$TEST_PORT" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
nc -z 127.0.0.1 "$TEST_PORT" >/dev/null 2>&1 || fail "proxy did not start on 127.0.0.1:$TEST_PORT"

echo "[INFO] Connecting test client"
mkfifo "$CLIENT_FIFO"
(
  cd "$ROOT_DIR"
  WS_URL="ws://127.0.0.1:$TEST_PORT/ws" GOCACHE=/tmp/go-build ./scripts/run_client.sh <"$CLIENT_FIFO" >"$CLIENT_LOG" 2>&1
) &
CLIENT_PID=$!
exec 3>"$CLIENT_FIFO"

expect_pattern "WELCOME " 15 || fail "did not receive WELCOME"

send_line 'HELLO smoke-test'
# Some DBs emit a login banner immediately, others do not.
# We validate true end-to-end behavior via successful login/command flow below.
expect_pattern "DATA " 5 || true

send_line 'SEND connect wizard wizardtest'
# Some runs show "*** Connected ***"; others may emit
# "*** Redirecting old connection to this port ***" first.
# We validate successful login by checking that a post-login command works.
expect_pattern "*** Connected ***" 5 || true

send_line 'SEND look'
expect_pattern "The First Room" 20 || fail "look response missing (login may have failed)"

send_line 'PING'
expect_pattern "PONG" 10 || fail "PING/PONG failed"

echo "[PASS] e2e relay smoke test succeeded"
