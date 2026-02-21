#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH="/opt/homebrew/bin:$PATH"

PROXY_LOG="$(mktemp -t moo-proxy-log.XXXXXX)"
CLIENT_LOG="$(mktemp -t moo-client-log.XXXXXX)"
CLIENT_FIFO="$(mktemp -u -t moo-client-fifo.XXXXXX)"
PROXY_PID=""
CLIENT_PID=""

cleanup() {
  set +e
  if [[ -n "$CLIENT_PID" ]]; then
    kill "$CLIENT_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$PROXY_PID" ]]; then
    kill "$PROXY_PID" >/dev/null 2>&1 || true
  fi
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
"$ROOT_DIR/scripts/run_local_moo.sh" up >/dev/null
"$ROOT_DIR/scripts/run_local_moo.sh" bootstrap >/dev/null

echo "[INFO] Starting proxy"
(
  cd "$ROOT_DIR"
  GOCACHE=/tmp/go-build ./scripts/run_proxy.sh
) >"$PROXY_LOG" 2>&1 &
PROXY_PID=$!

for _ in $(seq 1 30); do
  if nc -z 127.0.0.1 9000 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
nc -z 127.0.0.1 9000 >/dev/null 2>&1 || fail "proxy did not start on 127.0.0.1:9000"

echo "[INFO] Connecting test client"
mkfifo "$CLIENT_FIFO"
(
  cd "$ROOT_DIR"
  GOCACHE=/tmp/go-build ./scripts/run_client.sh <"$CLIENT_FIFO" >"$CLIENT_LOG" 2>&1
) &
CLIENT_PID=$!
exec 3>"$CLIENT_FIFO"

expect_pattern "WELCOME " 15 || fail "did not receive WELCOME"

printf 'HELLO smoke-test\n' >&3
expect_pattern "DATA Welcome to the LambdaCore database" 20 || fail "did not receive LambdaMOO welcome text"

printf 'SEND connect wizard wizardtest\n' >&3
expect_pattern "*** Connected ***" 20 || fail "wizard login failed through proxy"

printf 'SEND look\n' >&3
expect_pattern "The First Room" 20 || fail "look response missing"

printf 'PING\n' >&3
expect_pattern "PONG" 10 || fail "PING/PONG failed"

echo "[PASS] e2e relay smoke test succeeded"
