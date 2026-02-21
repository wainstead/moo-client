#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/scripts/wslineclient"

WS_URL="${WS_URL:-ws://127.0.0.1:9000/ws}" exec go run .
