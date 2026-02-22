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
- Phase 6: proxy LAN dev mode for phone-on-LAN testing (done)
- Phase 7: iOS relay client (`HELLO`, `RESUME`, `SEND`, `PING`) (done)
- Phase 8: minimal iOS chat UI layer (done)
- CLI plan (A-D): interactive/debug CLI, persisted resume state, classifier parity fixtures, scripted scenarios (done)

See `SPEC.md` for protocol and scope rules.
Testing instructions live in `TESTING.md`.
Top-level convenience commands are available via `Makefile` (run `make help`).
Development guidelines live in `HACKING.md`.
Coding-agent constraints live in `AGENT.md`.

## Remaining work

- Phase 9: iPhone sleep/resume validation checklist and fixes (see `SPEC.md` and `TESTING.md`)
- Testing strategy roadmap items in `docs/TEST_STRATEGY_PLAN.md`
- Host deployment helper scripts are planned (not implemented yet):
  - `scripts/deploy_netbsd_host.sh`
  - `scripts/deploy_linux_host.sh` (later)

## Documentation map

- `SPEC.md`: protocol, phase scope, and deployment planning
- `TESTING.md`: automated and manual test procedures
- `HACKING.md`: contributor workflow and architectural constraints
- `AGENT.md`: coding-agent operating rules for this repo
- `STATUS.md`: single-page project phase/testing status
- `docs/CLI_PLAN.md`: CLI design and implementation plan/history
- `docs/TEST_STRATEGY_PLAN.md`: testing roadmap and priorities

## Repository layout

- `proxy/` Go WebSocket<->TCP relay
- `core/` Rust event classifier engine and CLI
- `macos-app/` SwiftUI desktop client
- `ios-app/` iOS relay client module (`HELLO`, `SEND`, `PING`, `RESUME`)
  - includes iOS core classifier + minimal SwiftUI chat UI (occupants, messages, input)
- `scripts/` run/test/bootstrap scripts
- `docker-compose.moo.yml` local LambdaMOO container stack

## Architecture

```text
                                 (TCP :7777)
                      +-------------------------------+
                      |       LambdaMOO Server        |
                      |      (Docker/local host)      |
                      +---------------+---------------+
                                      ^
                                      | raw upstream bytes
                                      v
                      +-------------------------------+
                      |        PROXY (Go)             |
                      |  proxy/cmd + proxy/internal   |
                      |  - single upstream TCP session|
                      |  - rolling buffer + RESUME    |
                      +---------------+---------------+
                                      ^
                                      | WebSocket (/ws, :9000)
                   +------------------+------------------+
                   |                                     |
                   v                                     v
      +------------------------------+      +------------------------------+
      |    macOS Client (SwiftUI)    |      |    iOS Client (SwiftUI)      |
      |        macos-app/            |      |          ios-app/             |
      +---------------+--------------+      +---------------+--------------+
                      |                                     |
                      | raw DATA lines                     | raw DATA lines
                      v                                     v
      +------------------------------+      +------------------------------+
      |   Core Classifier (Rust)     |      |  iOS Core Classifier (Swift) |
      |          core/               |      |         MooIOSCore            |
      | Chat / Arrive / Leave/System |      | Chat / Arrive / Leave/System |
      +------------------------------+      +------------------------------+

Notes:
- The classifier maps raw MOO text lines into structured event types (`Chat`, `Arrive`, `Leave`, `System`) with byte offsets.
- Structured events are what the UI renders and uses for occupant/message state updates.
- UI layers consume structured events; they do not parse raw network text directly.
- Proxy is the shared transport/session authority for all connected clients.
```

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
cd moo-client
cp .env.moo.example .env.moo   # optional
./scripts/run_local_moo.sh up
./scripts/run_local_moo.sh bootstrap
```

### Start proxy

```bash
cd moo-client
./scripts/run_proxy.sh
```

Default bind: `127.0.0.1:9000`  
Upstream MOO: `127.0.0.1:7777`

For iPhone-on-LAN development, use:

```bash
cd moo-client
PROXY_MODE=lan ./scripts/run_proxy.sh
```

This binds `0.0.0.0:9000` (trusted local network only).

### Connect simple test client

```bash
cd moo-client
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
cd moo-client
./scripts/test_e2e.sh
```

This checks relay handshake, MOO login through proxy, command flow, and `PING`/`PONG`.
It resets local MOO state first to avoid stale-session flakes.

### CLI debug client (no GUI)

```bash
make cli-build
make cli-run
```

`moo-cli` now supports persisted session/offset state for resume testing:

```bash
cd core
cargo run --bin moo-cli -- connect --ws-url ws://127.0.0.1:9000/ws --state-file /tmp/moo-cli-state.json
```

Scripted CLI smoke test:

```bash
make cli-smoke
```

Scripted scenario mode (with richer trace output):

```bash
cd core
cargo run --bin moo-cli -- scenario \
  --ws-url ws://127.0.0.1:9000/ws \
  --scenario-file ../scripts/scenarios/resume_scenario.txt \
  --state-file /tmp/moo-cli-state.json \
  --json --trace
```

Scenario smoke test:

```bash
make cli-scenario
```

`cli-smoke` and `cli-scenario` also reset local MOO state before running.

Classifier parity check (shared fixtures across Rust and Swift):

```bash
make classifier-parity
```

### Clean up stale proxy processes

If you suspect an old proxy process is still running:

```bash
make everything-down  # recommended: stop MOO stack + all mooproxy processes
make everything-up    # start MOO + bootstrap + fresh local proxy on :9000
make proxy-status
make proxy-down       # stops listeners on TCP 9000
make proxy-down-all   # stops all mooproxy processes
```

## Build and test

Preferred (repo root):

```bash
make test
make coverage
make e2e
make classifier-parity
make cli-scenario
# or:
make check
```

Coverage notes:
- `make coverage` reports Go + Swift coverage with built-in tooling.
- Rust line coverage is included when `cargo-llvm-cov` is installed; otherwise Rust is reported as skipped.

Equivalent per-component commands:

```bash
cd proxy
go test ./...
go build ./...

cd ../core
cargo test
cargo build

cd ../macos-app
swift build

cd ../ios-app
swift build
swift run MooIOSRelaySelfTest
```

## Deploy model

Proxy is intended to bind localhost only and be reached by SSH tunnel:

```bash
ssh -L 9000:localhost:9000 <host>
```

Deployment automation scripts are planned but not implemented yet (tracked in `SPEC.md`).

```text
______       _ _ _              _ _   _         
| ___ \     (_) | |            (_) | | |        
| |_/ /_   _ _| | |_  __      ___| |_| |__      
| ___ \ | | | | | __| \ \ /\ / / | __| '_ \     
| |_/ / |_| | | | |_   \ V  V /| | |_| | | |    
\____/ \__,_|_|_|\__|   \_/\_/ |_|\__|_| |_|    
                                                
                                                
 _____           _                              
/  __ \         | |                             
| /  \/ ___   __| | _____  __  __ _ _ __  _ __  
| |    / _ \ / _` |/ _ \ \/ / / _` | '_ \| '_ \ 
| \__/\ (_) | (_| |  __/>  < | (_| | |_) | |_) |
 \____/\___/ \__,_|\___/_/\_(_)__,_| .__/| .__/ 
                                   | |   | |    
                                   |_|   |_|    

             Built with Codex.app
```
