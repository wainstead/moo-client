# CLI Plan: `moo-cli`

## Purpose

Create a debug-first command-line client for the `moo-client` stack so transport, resume behavior, and classification can be tested without depending on GUI clients.

This tool is intended to speed up development, improve reproducibility, and support CI-friendly regression checks.

## Why this is worth building

- Faster feedback loop than GUI testing
- Scriptable and repeatable protocol flows
- Better visibility into offsets/resume behavior
- Enables classifier validation outside macOS/iOS UI paths
- Useful for CI smoke/integration checks

## Current classifier landscape

There are currently two classifier implementations:

- Rust classifier (canonical shared core behavior)
  - `core/src/lib.rs`
- Swift classifier used by iOS side
  - `ios-app/Sources/MooIOSCore/CoreEvent.swift`

Both should be tested. A CLI-driven workflow can validate both.

## Goals

Build a CLI tool that can:

- Connect to proxy over WebSocket
- Send protocol commands (`HELLO`, `RESUME`, `SEND`, `PING`)
- Display raw stream and/or classified events
- Track and persist session + offset state
- Reconnect and verify replay behavior
- Support scripted, non-interactive testing mode

## Non-goals

- No protocol changes
- No authentication implementation
- No credential storage beyond local test/dev config
- No auto-generated MOO commands by proxy/client

## Proposed location

- Rust executable target inside `core`:
  - `core/src/bin/moo-cli.rs`

Optional later:
- Swift executable target for classifier parity checks in `ios-app`

## CLI behavior (MVP)

Primary command:

- `moo-cli connect [flags]`

Flags:

- `--ws-url ws://127.0.0.1:9000/ws`
- `--session-id <id>`
- `--resume-offset <n>`
- `--state-file <path>`
- `--raw`
- `--events`
- `--json`
- `--no-resume`
- `--trace`

Interactive input:

- Plain line -> send `SEND <line>`
- `/ping` -> send `PING`
- `/offset` -> print current offset
- `/reconnect` -> reconnect using saved session/offset
- `/quit` -> disconnect and exit

## Runtime modules inside `moo-cli`

1. Transport client
- WebSocket connect/read/write
- Parse text control lines and binary `DATA` frames

2. Stream/offset engine
- Reassemble complete lines from raw bytes
- Track offset as "next byte expected"

3. Classifier adapter
- Classify each line into structured events
- Use Rust classifier by default

4. State store
- Persist `session_id` and `last_offset` (opt-in file)

5. Output renderer
- Raw mode
- Event mode
- JSON mode
- Trace metadata mode

## Testing and debugging workflows enabled

1. Fast login debug
- connect + login via CLI
- inspect raw and structured output

2. Resume correctness checks
- capture offset
- disconnect/reconnect
- verify replay and no gaps

3. Protocol-level troubleshooting
- isolate transport behavior from GUI issues

4. CI smoke checks
- script CLI actions
- assert expected checkpoints (`WELCOME`, connected, `PONG`, `look` output)

## Testing both classifiers from CLI workflows

Yes, this is feasible and recommended.

### Shared fixture strategy

Define fixture corpus (e.g. JSONL) with:
- `line`
- `offset`
- expected normalized event payload

### Rust validation

- Fixture runner in `core`
- Compare Rust classifier output against expected fixtures

### Swift validation

- Add Swift executable target in `ios-app` to run same fixtures
- Emit normalized output and compare against expected fixtures

### Parity target

Add top-level task that runs both fixture suites and fails on divergence.

## Proposed implementation phases

### Phase A

- Implement `moo-cli` transport + interactive mode
- Add raw/event/json output
- Add offset tracking

### Phase B

- Add state file persistence (`session_id`, `last_offset`)
- Add reconnect helpers and resume controls

Status: complete

### Phase C

- Add shared classifier fixtures
- Add Rust fixture tests
- Add Swift fixture runner/tests
- Add parity check target

### Phase D

- Add richer tracing and scripted scenario mode
- Integrate CLI scenario checks into CI flow

## Makefile integration (planned)

Add targets:

- `make cli-build`
- `make cli-run`
- `make cli-smoke`
- `make classifier-parity`

## Documentation updates (planned)

- `README.md`: quick CLI debug section
- `TESTING.md`: CLI-first troubleshooting and scenario steps
- `core/README.md`: CLI usage examples

## Risks and considerations

- Dependency choice for WebSocket in Rust should stay maintainable
- Offset semantics must stay aligned with proxy contract
- Swift parity runner depends on Swift toolchain availability
- MOO text can evolve; classifier rules should remain easy to update

## Success criteria

`moo-cli` allows developers to quickly:
- connect/login/send commands
- inspect raw + classified output
- test reconnect/resume deterministically
- verify classifier behavior across Rust and Swift implementations

without requiring GUI clients.
