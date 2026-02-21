#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${MOO_SERVER_CMD:-}" ]]; then
  echo "Set MOO_SERVER_CMD to your local LambdaMOO launch command."
  echo "Example: MOO_SERVER_CMD='~/lambda-moo/moo db/moo.db 7777' ./scripts/run_local_moo.sh"
  exit 1
fi

exec bash -lc "$MOO_SERVER_CMD"
