# STATUS

Project status snapshot for `moo-client`.

## Phase status

- Phase 1: Basic relay (complete)
- Phase 2: Rolling buffer (complete)
- Phase 3: Resume by offset (complete)
- Phase 4: Rust core classifier (complete)
- Phase 5: macOS minimal UI (complete)
- Phase 6: LAN proxy dev mode (complete)
- Phase 7: iOS relay client (complete)
- Phase 8: iOS minimal UI (complete)
- Phase 9: iPhone sleep/resume validation and fixes (in progress)

## CLI plan status

- `docs/CLI_PLAN.md` Phase A-D: complete
- Makefile integration: complete
- Documentation updates: complete

## Testing strategy status

Tracked in `docs/TEST_STRATEGY_PLAN.md`:
- Proxy integration tests with deterministic harness: planned
- Classifier fixture expansion/parity: in progress
- Coverage gating policy: in progress
- CI fast/slow lane split: planned
- Long-run resilience suite: planned
- Human acceptance checklist for invisible reconnect: in progress

## Deployment automation status

Planned (not implemented):
- `scripts/deploy_netbsd_host.sh`
- `scripts/deploy_linux_host.sh` (later)

Deployment model today:
- Proxy default bind `127.0.0.1:9000`
- Remote access via SSH tunnel (`ssh -L 9000:localhost:9000 <host>`)
