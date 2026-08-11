# HACKING

Developer notes for working on `moo-client`.

## Philosophy

This is a systems behavior project, not a UI polish project.

Priority order:
1. Reconnect correctness
2. Protocol correctness
3. Simplicity
4. Performance

## Hard constraints

- Do not change protocol unless explicitly requested.
- Do not add features outside the active phase/scope.
- No auth implementation.
- No credential storage outside explicit local test config (`.env.moo`).
- Proxy never generates commands on its own.
- UI must not parse raw network text directly; raw text classification belongs in `core/`.

## Protocol (locked)

Client -> Proxy
- `HELLO <session-id>`
- `RESUME <offset>`
- `SEND <text>\n`
- `PING`

Proxy -> Client
- `WELCOME <session-id>`
- `RESUMED <actual-offset>`
- `DATA <raw-bytes>`
- `PONG`

Offsets are against raw upstream byte stream.
`RESUMED <actual-offset>` is sent after each accepted `RESUME` and before any replayed `DATA`; clients must reset their next expected byte offset to `<actual-offset>` before parsing later `DATA`.

## Main components

### `proxy/` (Go)

- Maintains one upstream TCP connection to MOO.
- Accepts WebSocket clients.
- Broadcasts upstream bytes as `DATA`.
- Maintains stream offset and 1 MB rolling buffer.
- Supports explicit `RESUME <offset>` replay from available window.

Key files:
- `proxy/cmd/mooproxy/main.go`
- `proxy/internal/relay.go`
- `proxy/internal/ring_buffer.go`
- `proxy/internal/ws.go`

### `core/` (Rust)

- Classifies incoming text lines using regex.
- Emits JSON events with offset.
- Event kinds: `chat`, `arrive`, `leave`, `system`.

Key files:
- `core/src/lib.rs`
- `core/src/main.rs`
- `core/tests/classify.rs`

### `macos-app/` (Swift)

- Minimal chat UI with occupant list, messages, input.
- Relay client receives proxy `DATA` and passes lines into `core` bridge.
- UI consumes structured events only.

Key files:
- `macos-app/Sources/MooMacApp/RelayClient.swift`
- `macos-app/Sources/MooMacApp/CoreClassifierBridge.swift`
- `macos-app/Sources/MooMacApp/AppViewModel.swift`

### `ios-app/` (Swift)

- Phase 7 relay client module and Phase 8 minimal SwiftUI UI.
- Handles proxy protocol commands:
  - `HELLO <session-id>`
  - `RESUME <offset>`
  - `SEND <text>`
  - `PING`
- Tracks session ID and last offset in a pluggable state store.
- UI uses a core classification layer (`MooIOSCore`) so views do not parse raw relay text.

Key files:
- `ios-app/Sources/MooIOSRelay/MooRelayClient.swift`
- `ios-app/Sources/MooIOSRelay/RelayProtocol.swift`
- `ios-app/Sources/MooIOSRelay/RelayStateStore.swift`
- `ios-app/Sources/MooIOSRelay/RelayStreamParser.swift`
- `ios-app/Sources/MooIOSCore/CoreEvent.swift`
- `ios-app/Sources/MooIOSUI/IOSChatViewModel.swift`
- `ios-app/Sources/MooIOSUI/IOSChatView.swift`

## Local infra

### LambdaMOO container

- Compose file: `docker-compose.moo.yml`
- Runner: `scripts/run_local_moo.sh`
- Bootstrap: `scripts/moo/bootstrap_moo.sh`
- Credentials/room names: `.env.moo` (copy from `.env.moo.example`)

### Smoke test

- `scripts/test_e2e.sh`
- Validates end-to-end relay + login flow.

## Typical workflows

Show available top-level tasks:

```bash
make help
```

Start local MOO:

```bash
make moo-up
make moo-bootstrap
```

Run proxy:

```bash
./scripts/run_proxy.sh
```

Run proxy in LAN dev mode (for phone -> laptop testing):

```bash
PROXY_MODE=lan ./scripts/run_proxy.sh
```

Run smoke test:

```bash
make e2e
```

Run CLI smoke test:

```bash
make cli-smoke
```

Run scripted CLI scenario smoke test:

```bash
make cli-scenario
```

Run shared classifier parity check:

```bash
make classifier-parity
```

For manual reconnect debugging with persisted offset/session:

```bash
cd core
cargo run --bin moo-cli -- connect --ws-url ws://127.0.0.1:9000/ws --state-file /tmp/moo-cli-state.json
```

Run full repo test suite:

```bash
make test
```

Run multi-language coverage summary:

```bash
make coverage
```

Run only iOS relay self-test:

```bash
cd ios-app
swift run MooIOSRelaySelfTest
```

## Known caveats

- `bootstrap_moo.sh` assumes common LambdaCore command verbs.
  If you swap DB/core, adjust that script accordingly.
- Keep proxy and MOO separate in local/dev/deploy topology.
