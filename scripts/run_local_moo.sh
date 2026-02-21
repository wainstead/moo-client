#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.moo.yml"
ENV_FILE="$ROOT_DIR/.env.moo"

compose_args=(-f "$COMPOSE_FILE")
if [[ -f "$ENV_FILE" ]]; then
  compose_args+=(--env-file "$ENV_FILE")
fi

usage() {
  cat <<USAGE
Usage:
  ./scripts/run_local_moo.sh up         # start LambdaMOO container
  ./scripts/run_local_moo.sh bootstrap  # run one-time DB bootstrap script
  ./scripts/run_local_moo.sh logs       # stream LambdaMOO logs
  ./scripts/run_local_moo.sh down       # stop stack
  ./scripts/run_local_moo.sh reset      # stop stack + delete persistent volume
USAGE
}

cmd="${1:-up}"

case "$cmd" in
  up)
    docker compose "${compose_args[@]}" up -d lambdamoo
    ;;
  bootstrap)
    docker compose "${compose_args[@]}" up -d lambdamoo
    docker compose "${compose_args[@]}" run --rm moo-bootstrap
    ;;
  logs)
    docker compose "${compose_args[@]}" logs -f lambdamoo
    ;;
  down)
    docker compose "${compose_args[@]}" down
    ;;
  reset)
    docker compose "${compose_args[@]}" down -v
    ;;
  *)
    usage
    exit 1
    ;;
esac
