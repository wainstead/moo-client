# moo-client

`moo-client` is a persistent relay + client stack for LambdaMOO.

Goal: keep one continuous upstream TCP session to MOO while clients can attach/detach over WebSocket, so a sleeping device can resume without a visible MOO reconnect.
Architecture model: single upstream MOO connection, multiple concurrent WebSocket clients.

## Current status

- Phase 1: Basic relay (done)
- Phase 2: 1 MB rolling buffer (done)
- Phase 3: resume by upstream byte offset (done)
- Phase 4: Rust core event classifier (`Chat`, `Arrive`, `Leave`, `System`) (done)
- Phase 5: minimal macOS app (done)

See `SPEC.md` for protocol and scope rules.

## Repository layout

- `proxy/` Go WebSocket<->TCP relay
- `core/` Rust event classifier engine and CLI
- `macos-app/` SwiftUI desktop client
- `ios-app/` iOS relay client module (`HELLO`, `SEND`, `PING`, `RESUME`)
- `scripts/` run/test/bootstrap scripts
- `docker-compose.moo.yml` local LambdaMOO container stack

## Quick start (local)

### Prerequisites

- macOS (Apple Silicon tested)
- Homebrew
- Go (current)
- Rust (`cargo`, `rustc`)
- Swift toolchain / Xcode CLT
- Docker + Colima

### Start local LambdaMOO

```bash
cd /Users/swain/Projects/moo-client
cp .env.moo.example .env.moo   # optional
./scripts/run_local_moo.sh up
./scripts/run_local_moo.sh bootstrap
```

### Start proxy

```bash
cd /Users/swain/Projects/moo-client
./scripts/run_proxy.sh
```

Default bind: `127.0.0.1:9000`  
Upstream MOO: `127.0.0.1:7777`

For iPhone-on-LAN development, use:

```bash
cd /Users/swain/Projects/moo-client
PROXY_MODE=lan ./scripts/run_proxy.sh
```

This binds `0.0.0.0:9000` (trusted local network only).

### Connect simple test client

```bash
cd /Users/swain/Projects/moo-client
./scripts/run_client.sh
```

Example protocol lines:

```text
HELLO test-session
SEND connect wizard wizardtest
SEND look
PING
```

### One-command smoke test

```bash
cd /Users/swain/Projects/moo-client
./scripts/test_e2e.sh
```

This checks relay handshake, MOO login through proxy, command flow, and `PING`/`PONG`.

## Build and test

```bash
cd /Users/swain/Projects/moo-client/proxy
go test ./...
go build ./...

cd /Users/swain/Projects/moo-client/core
cargo test
cargo build

cd /Users/swain/Projects/moo-client/macos-app
swift build

cd /Users/swain/Projects/moo-client/ios-app
swift build
swift run MooIOSRelaySelfTest
```

## Deploy model

Proxy is intended to bind localhost only and be reached by SSH tunnel:

```bash
ssh -L 9000:localhost:9000 panix
```
