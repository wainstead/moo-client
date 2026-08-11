# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- See `AGENT.md` for repo-specific coding constraints and validation expectations.
- Protocol details live in `SPEC.md` and `HACKING.md`; replay is explicit through `RESUME <offset>`, while `HELLO <session-id>` is handshake identity only.
- Deterministic proxy replay coverage lives in `proxy/internal/relay_integration_test.go`; keep Phase 9 replay fixes pinned there before relying on manual iPhone evidence.
- The in-repo physical-device Phase 9 host app is `ios-host-app/Phase9Host.xcodeproj`; fresh-checkout run steps and evidence requirements live in `TESTING.md`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
