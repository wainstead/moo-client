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
- primary in-repo iPhone sample path for Phase 9 acceptance

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

## 5. Manual test: iPhone sample app

Phase 9 uses the checked-in sample app at `ios-host-app/Phase9Host.xcodeproj`.
It imports the local `ios-app` Swift package, presents `IOSChatView`, persists
resume state with `UserDefaultsRelayStateStore`, and reconnects when the app
returns to the active scene.

Fresh-checkout physical iPhone setup:

1. Start local MOO and bootstrap it:

```bash
cd moo-client
cp .env.moo.example .env.moo   # optional if already present
./scripts/run_local_moo.sh reset
./scripts/run_local_moo.sh up
./scripts/run_local_moo.sh bootstrap
```

2. Find the laptop LAN IP used by the iPhone:

```bash
ipconfig getifaddr en0
```

If Wi-Fi is not `en0`, use the active trusted LAN interface instead.

3. Edit `ios-host-app/Phase9Host/Phase9HostConfig.swift`:

```swift
static let defaultWebSocketURLString = "ws://<laptop-lan-ip>:9000/ws"
```

The checked-in default is `ws://127.0.0.1:9000/ws`; it is an obvious safe edit
point, not a physical-device default.

4. Start the proxy in trusted-LAN mode with trace logging:

```bash
cd moo-client
MOO_PROXY_TRACE=1 PROXY_MODE=lan UPSTREAM_ADDR=127.0.0.1:7777 \
  ./scripts/run_proxy.sh 2>&1 | tee /tmp/moo-phase9-proxy.log
```

5. Open `ios-host-app/Phase9Host.xcodeproj` in Xcode.
6. Select the `Phase9Host` target, set a development team/signing identity if needed, and run it on a physical iPhone on the same trusted LAN.
7. In the app, verify the top bar shows `ws://<laptop-lan-ip>:9000/ws`, the current offset, and connection state.
8. Send `connect regular regulartest`, `look`, and one `say <run-id>-iphone-ready` command. Verify the feed, event log, and Xcode console show `HELLO`, `RESUME <offset>`, `WELCOME`, `DATA offset=...`, and monotonic offsets.

Secondary external-host path:

If the checked-in sample cannot be used, create a small Xcode iOS app outside
the repo, add the local package dependency `<path-to-repo>/ios-app`, instantiate
`IOSChatViewModel`, present `IOSChatView`, pass a
`UserDefaultsRelayStateStore`, and reconnect on active scene. Keep the in-repo
sample as the primary Phase 9 path whenever possible.

## 6. Resume behavior checks (manual)

For quick reconnect validation:
1. Connect and login from the iPhone sample.
2. Close/suspend the app.
3. Produce room messages from another direct MOO client.
4. Reopen the app and confirm missed lines are replayed.

Phase 9 acceptance run (iPhone invisible reconnect) pass criteria:
- observer client does not see disconnect/reconnect text for the sleeping iPhone session
- iPhone resumes and sees continuity (no missing expected lines during suspend window)
- iPhone can continue sending commands after resume

Failure criteria:
- any reconnect artifact visible to observer
- missing expected lines after resume
- failed command flow after resume

Repeatable Phase 9 evidence procedure:

1. Create a run ID and artifact directory:

```bash
RUN_ID="phase9-$(date -u +%Y%m%dT%H%M%SZ)"
ARTIFACT_DIR="/tmp/moo-$RUN_ID"
mkdir -p "$ARTIFACT_DIR"
git rev-parse HEAD | tee "$ARTIFACT_DIR/commit.txt"
```

2. Start a direct observer, not a second WebSocket client:

```bash
script -q "$ARTIFACT_DIR/observer.log" nc 127.0.0.1 7777
```

In the observer:

```text
connect wizard wizardtest
look
say <RUN_ID>-observer-ready
```

3. Start iPhone screen recording. In `Phase9Host`, send:

```text
connect regular regulartest
look
say <RUN_ID>-before-sleep
```

Record the visible offset before sleep.

4. Lock or background the iPhone for at least 4 minutes. This intentionally
exceeds the proxy WebSocket read deadline. During the sleep window, send from
the direct observer:

```text
say <RUN_ID>-sleep-window-start
say <RUN_ID>-sleep-001
say <RUN_ID>-sleep-002
say <RUN_ID>-sleep-003
```

5. Unlock/foreground the iPhone. Expected evidence:
- the app reconnects without a manual proxy restart
- app/Xcode logs show `RESUME <pre-sleep-offset>`
- app feed shows all sleep-window markers in order
- app offsets remain monotonic
- proxy trace shows one upstream session and a replay window for the requested offset

6. Send from the iPhone:

```text
say <RUN_ID>-after-resume
look
```

Then send from the observer:

```text
say <RUN_ID>-sleep-window-end
```

7. Preserve:
- `/tmp/moo-phase9-proxy.log`
- `$ARTIFACT_DIR/observer.log`
- iPhone screen recording
- Xcode console or device log containing the Phase 9 event lines
- run notes with device model, iOS version, macOS version, LAN IP, sleep duration, and pass/fail observations

Do not mark physical Phase 9 acceptance passed unless this procedure was run
on a physical iPhone.

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
