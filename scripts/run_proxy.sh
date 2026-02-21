#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/proxy"

LISTEN_ADDR="${LISTEN_ADDR:-127.0.0.1:9000}"
UPSTREAM_ADDR="${UPSTREAM_ADDR:-127.0.0.1:7777}"

exec go run ./cmd/mooproxy -listen "$LISTEN_ADDR" -upstream "$UPSTREAM_ADDR"
