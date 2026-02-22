# Testing Strategy Plan

## Goal

Increase confidence in reconnect correctness and protocol behavior while keeping fast local feedback loops.

Current strengths already in place:
- protocol smoke scripts (`test_e2e.sh`, `test_cli_smoke.sh`, `test_cli_scenario.sh`)
- classifier parity checks across Rust and Swift (`test_classifier_parity.sh`)
- multi-language coverage reporting (`make coverage`)

This plan focuses on closing risk gaps and making test results more deterministic and enforceable.

## Priority roadmap

### 1. Proxy behavior integration tests (highest value)

Add focused integration tests around relay invariants in `proxy/internal`:
- single upstream TCP session with multiple WebSocket clients
- attach/detach behavior with no unintended upstream reconnect
- resume edge cases:
  - exact offset
  - stale offset
  - future offset
  - buffer-wrap offset
- upstream disconnect behavior:
  - clients receive disconnect signal
  - `SEND` is rejected after upstream loss
  - proxy does not auto-reconnect
- malformed protocol/control lines and frame boundary handling

Deliverables:
- new Go test files in `proxy/internal`
- deterministic assertions on byte-for-byte replay and control responses

### 2. Deterministic fake-MOO harness

Create a lightweight scripted TCP test server used by proxy tests:
- emits controlled upstream byte sequences
- supports scripted disconnects and timing points
- captures client `SEND` commands for assertions

Why:
- removes LambdaMOO DB variability from protocol tests
- enables deterministic, repeatable resume/reconnect test cases

Deliverables:
- harness package under `proxy/internal` (or `proxy/testutil`)
- integration tests migrated to harness for core protocol correctness
- Docker LambdaMOO retained for smoke/regression only

### 3. Classifier fixture corpus expansion

Extend shared fixtures in `fixtures/classifier_fixtures.jsonl`:
- real transcript-derived lines
- CRLF and blank-line edge cases
- colon and whitespace edge cases
- unicode/non-ASCII text samples

Maintain Rust/Swift parity gate as required CI step.

Deliverables:
- expanded fixture set
- corresponding expected normalized events
- parity check remains enforced via `make classifier-parity`

### 4. Long-run resilience tests

Add stress-style tests for session continuity and replay correctness:
- repeated reconnect loops (e.g., 100 cycles)
- randomized sequences of send/reconnect/wait/ping
- assertions for:
  - no missing bytes
  - no duplicate replay beyond expected
  - no lingering proxy listeners/process leaks

Deliverables:
- new scripted stress target (e.g. `make cli-stress`)
- post-run listener/process checks

### 5. Coverage gating policy

Evolve from reporting-only to enforceable quality gates:
- keep `make coverage` summary
- add `make coverage-check` with initial low thresholds by component
- ratchet thresholds upward over time
- add diff coverage checks for changed files where practical
- exclude generated/runner artifacts from Swift totals where feasible

Deliverables:
- threshold config file (documented)
- coverage-check script and Make target
- CI failure on threshold regressions

### 6. CI lane separation

Split test execution by speed/scope:
- fast lane (per PR):
  - unit tests
  - proxy integration tests (fake-MOO harness)
  - classifier parity
- slow lane (merge/nightly):
  - Docker e2e
  - CLI scenario smoke
  - long-run resilience suite

Deliverables:
- CI workflow definitions with clear pass/fail gates
- docs for local reproduction of each lane

### 7. Human acceptance checklist for invisible reconnect

Define a formal human-run checklist for the milestone:
- sleeping client resumes with no MOO-visible disconnect/reconnect message
- observer client confirms no reconnect artifacts
- message continuity confirmed across suspend interval

Deliverables:
- checklist in `TESTING.md` (or dedicated acceptance doc)
- explicit pass/fail criteria for Phase 9 milestone validation

## Suggested implementation order

1. Proxy behavior integration tests
2. Fake-MOO harness
3. Classifier fixture expansion
4. Coverage check gates
5. CI lane split
6. Long-run resilience suite
7. Human acceptance checklist finalization

## Exit criteria

Testing strategy is considered upgraded when:
- protocol correctness is primarily verified by deterministic integration tests
- parity fixtures are broad and stable across Rust/Swift
- coverage includes enforced minimum gates
- CI clearly separates fast and slow confidence lanes
- invisible reconnect has a repeatable acceptance checklist
