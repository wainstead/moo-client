#!/bin/sh
set -eu

# Bootstraps first-run LambdaMOO state: wizard password, regular user, and two rooms.
# Idempotence is marker-file based against the persistent volume.

MARKER="/home/moo/.bootstrap_done"
LOG="/home/moo/bootstrap.log"

if [ -f "$MARKER" ]; then
  echo "bootstrap already completed"
  exit 0
fi

apk add --no-cache netcat-openbsd >/dev/null

HOST="${MOO_HOST:-lambdamoo}"
PORT="${MOO_PORT:-7777}"
WIZARD_LOGIN="${WIZARD_LOGIN:-wizard}"
WIZARD_CONNECT_PASSWORD="${WIZARD_CONNECT_PASSWORD:-}"
WIZARD_PASSWORD="${WIZARD_PASSWORD:-wizardtest}"
REGULAR_USERNAME="${REGULAR_USERNAME:-regular}"
REGULAR_PASSWORD="${REGULAR_PASSWORD:-regulartest}"
ROOM_ONE_NAME="${ROOM_ONE_NAME:-Room One}"
ROOM_TWO_NAME="${ROOM_TWO_NAME:-Room Two}"

tries=0
until nc -z "$HOST" "$PORT"; do
  tries=$((tries + 1))
  if [ "$tries" -gt 120 ]; then
    echo "timed out waiting for $HOST:$PORT"
    exit 1
  fi
  sleep 1
done

# LambdaMOO command syntax can vary with DB/core. These defaults target common LambdaCore commands.
# If your DB uses different verbs, adjust the command block in this script.
{
  sleep 1
  if [ -n "$WIZARD_CONNECT_PASSWORD" ]; then
    printf 'connect %s %s\n' "$WIZARD_LOGIN" "$WIZARD_CONNECT_PASSWORD"
  else
    printf 'connect %s\n' "$WIZARD_LOGIN"
  fi
  sleep 1

  # Set/update wizard password for local testing.
  printf '@password %s\n' "$WIZARD_PASSWORD"
  sleep 1

  # Create test regular user and set password.
  printf '@make-player %s\n' "$REGULAR_USERNAME"
  sleep 1
  printf '@newpassword %s %s\n' "$REGULAR_USERNAME" "$REGULAR_PASSWORD"
  sleep 1

  # Create two rooms.
  printf '@dig %s\n' "$ROOM_ONE_NAME"
  sleep 1
  printf '@dig %s\n' "$ROOM_TWO_NAME"
  sleep 1

  printf '@quit\n'
} | nc "$HOST" "$PORT" | tee "$LOG"

# Basic guard: if we never connected, fail so bootstrap can be retried.
if ! grep -qi "connected" "$LOG"; then
  echo "bootstrap did not confirm login; inspect $LOG"
  exit 1
fi

touch "$MARKER"
echo "bootstrap complete"
