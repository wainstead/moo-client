# AGENT.md

Instructions for coding agents (Codex, Claude Code, etc.) working in this repo.

## Objectives

- Preserve protocol correctness.
- Preserve reconnect behavior.
- Make minimal scoped changes.
- Keep implementation pragmatic and testable.

## Non-negotiable rules

1. Do not modify the wire protocol unless explicitly requested.
2. Do not implement features beyond the requested phase/task.
3. Do not add authentication.
4. Do not store real credentials.
5. Proxy must never invent or emit user commands by itself.
6. UI must not parse raw network text; classification belongs in `core/`.

## Architecture boundaries

- `proxy/` handles transport, sessions, buffering, resume.
- `core/` handles text->event classification.
- `macos-app/` renders state and sends user input.
- `scripts/` handles local ops/testing/bootstrap.

Do not blur these responsibilities.

## Change policy

- Prefer small patches over broad rewrites.
- Keep defaults bound to localhost for relay/MOO (`127.0.0.1`).
- Prioritize correctness over optimization.
- If assumptions are uncertain, state them clearly in commit messages or PR notes.

## Required validation before commit

At minimum, run what is relevant to changed components:

- Proxy: `cd proxy && go test ./... && go build ./...`
- Core: `cd core && cargo test`
- macOS app: `cd macos-app && swift build`
- iOS relay module: `cd ios-app && swift build && swift run MooIOSRelaySelfTest`
- End-to-end: `./scripts/test_e2e.sh`

If a command cannot run in the current environment, state that explicitly.

## Local stack expectations

- Use `docker-compose.moo.yml` for local LambdaMOO.
- Use `./scripts/run_local_moo.sh bootstrap` for initial DB setup.
- Keep proxy separate from MOO compose stack.

## Deliverable quality

When finishing work, include:
- what changed
- why it changed
- how it was verified
- any remaining risks/gaps

## Testing doc maintenance

- Keep `TESTING.md` current when test commands, manual validation flow, or runtime setup changes.
- If a change affects human testing steps, update `TESTING.md` in the same commit when practical.
