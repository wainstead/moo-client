# TESTING.md

Human and automated testing guide for `moo-client`.

## Install / checkout

Clone the repository first:

```bash
git clone https://github.com/wainstead/moo-client.git
cd moo-client
```

All commands below assume you are in the repo root.

## Scope

This document covers:
- automated checks for `proxy`, `core`, `ios-app`, and `macos-app`
- local end-to-end testing against Dockerized LambdaMOO
- manual click testing for macOS app
- practical iPhone testing path for current Phase 8 state

## Prerequisites

- macOS (Apple Silicon tested)
- Homebrew
- Go, Rust (`cargo`/`rustc`), Swift/Xcode CLT
- Docker + Colima running

## 1. Automated verification

Preferred (from repo root):

```bash
make test   # language-level checks
make coverage  # multi-language coverage summary
make e2e    # end-to-end smoke test against local MOO
make classifier-parity  # shared Rust/Swift classifier fixture parity
make cli-scenario  # scripted moo-cli scenario smoke test
# or:
make check  # test + e2e + classifier parity + cli scenario
```

Equivalent manual commands:

```bash
cd proxy
go test ./...
go build ./...

cd ../core
cargo test
cargo build

cd ../ios-app
swift build
swift test
swift run MooIOSRelaySelfTest

cd ../macos-app
swift build
```

## 2. Start local LambdaMOO

From repo root:

```bash
cp .env.moo.example .env.moo   # optional: copy default local MOO credentials/settings
./scripts/run_local_moo.sh up  # start LambdaMOO container in background
./scripts/run_local_moo.sh bootstrap  # initialize wizard/user/rooms (safe to rerun)
```

If you had previous dev runs, clear stale proxies before testing:

```bash
make everything-down   # recommended: stop local MOO stack + all mooproxy processes
make proxy-status      # show running mooproxy listeners/processes
make proxy-down-all    # stop all local mooproxy processes
```

Useful lifecycle commands:

```bash
./scripts/run_local_moo.sh logs   # follow server logs (does not exit; press Ctrl-C to stop following)
./scripts/run_local_moo.sh down   # stop containers, keep persistent DB volume
./scripts/run_local_moo.sh reset  # stop containers and delete persistent DB volume
```

## 3. End-to-end smoke test (recommended)

Runs relay + login + command-flow checks against local MOO:

```bash
./scripts/test_e2e.sh
```

Note: this script performs a local MOO `reset` first (recreates the Docker volume) to avoid stale-session flakes.

Expected final line:

```text
[PASS] e2e relay smoke test succeeded
```

## 3b. CLI debug flow (no GUI)

Build and run `moo-cli`:

```bash
make cli-build
make cli-run  # add --state-file /tmp/moo-cli-state.json for persisted resume state
```

Then in the interactive session, try:

```text
connect wizard wizardtest
look
/ping
/offset
/resume 0
/reconnect
/quit
```

Or run a scripted smoke check:

```bash
make cli-smoke
```

Note: `cli-smoke` and `cli-scenario` also reset local MOO state before running.

Run scripted scenario mode check:

```bash
make cli-scenario
```

## 4. Manual click test: macOS app

1. Build core binary:

```bash
cd core
cargo build
```

2. Run macOS app:

```bash
cd macos-app
MOO_WS_URL=ws://127.0.0.1:9000/ws \
MOO_CORE_BIN=../core/target/debug/moo-core \
swift run MooMacApp
```

3. In UI:
- Connect (auto-connect on launch, or click `Connect`)
- Send `connect wizard wizardtest`
- Send `look`
- Verify messages show in feed
- Verify occupant/system list updates
- Disconnect and reconnect once

## 5. Manual test: iPhone (current state)

Phase 8 provides iOS core + UI modules, but not a standalone iOS host app target in this repo.

To click test on iPhone now:
1. Create a small iOS host app in Xcode.
2. Add local package dependency: `<path-to-repo>/ios-app`.
3. Use `IOSChatViewModel` + `IOSChatView` in host app.
4. Connect to laptop LAN proxy URL: `ws://<laptop-lan-ip>:9000/ws`.
5. Ensure laptop proxy is running in LAN mode:

```bash
cd moo-client
PROXY_MODE=lan ./scripts/run_proxy.sh
```

6. On iPhone (same trusted LAN), verify connect/send/feed behavior.

## 6. Resume behavior checks (manual)

For reconnect validation:
1. Connect and login.
2. Close/suspend client.
3. Produce room messages from another client.
4. Reconnect and confirm missed lines are replayed.

Phase 9 acceptance run (iPhone invisible reconnect) pass criteria:
- observer client does not see disconnect/reconnect text for the sleeping iPhone session
- iPhone resumes and sees continuity (no missing expected lines during suspend window)
- iPhone can continue sending commands after resume

Failure criteria:
- any reconnect artifact visible to observer
- missing expected lines after resume
- failed command flow after resume

## 7. Test data defaults

From `.env.moo.example` defaults:
- wizard user: `wizard`
- wizard password: `wizardtest`
- regular user: `regular`
- regular password: `regulartest`

## 8. Updating this file

When changing behavior, protocol handling, scripts, app launch flow, or validation commands:
- update `TESTING.md` in the same commit when practical
- include new expected outputs or failure signatures where useful

## 9. Strategy roadmap tracking

Longer-term testing roadmap and priorities are tracked in:
- `docs/TEST_STRATEGY_PLAN.md`

Use this file (`TESTING.md`) for runnable procedures and expected outcomes.
Use the strategy plan for planned/in-progress improvements.
