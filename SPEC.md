# moo-client SPEC

Phase tracking for the relay/client system.

Protocol summary: line-oriented control over WebSocket text frames; `DATA` binary frames carry raw upstream bytes; `RESUME` replays by byte offset.

## Current status

- Phase 1 (Basic Relay): implemented
- Phase 2 (Rolling Buffer): implemented
- Phase 3 (Resume Support): implemented
- Phase 4 (Core Engine): implemented
- Phase 5 (macOS UI): implemented
- Phase 6 (LAN dev mode for proxy): implemented
- Phase 7 (iOS relay client): implemented
- Phase 8 (iOS minimal UI): implemented

## Next milestone

iPhone client connects to proxy running on laptop, then to LambdaMOO.

### Connection decision

Chosen: Option A (simplest working path for local development).

- Proxy listens on laptop LAN interface for dev testing: `0.0.0.0:9000`
- iPhone connects to: `ws://<laptop-lan-ip>:9000/ws`
- Scope for this mode is trusted local network only

Deployment model remains unchanged:

- Production/tunneled mode should stay localhost-bound (`127.0.0.1:9000`)
- Access should be via SSH tunnel when deployed remotely

## Planned phases

- Phase 9: iPhone sleep/resume validation checklist and fixes

## Future deployment automation (planned, not implemented)

Deployment helper scripts should be host-generic rather than provider-specific.

Planned script naming:
- `scripts/deploy_netbsd_host.sh`
- `scripts/deploy_linux_host.sh` (later)

Planned behavior:
- caller provides host details and runtime settings as arguments
- script does not hardcode a specific host (e.g., Panix)
- NetBSD deployment should target only the Go proxy binary
- default remote bind remains `127.0.0.1:9000` for SSH-tunnel usage

## Locked protocol

Proxy model: single upstream TCP session to MOO, multiple WebSocket clients attached to that session.

Offset semantics: offset is the 0-based index of the next upstream byte expected by the client (one past the last applied byte).

Client -> Proxy:
- HELLO <session-id>
- RESUME <offset>
- SEND <text>\n
- PING

Proxy -> Client:
- WELCOME <session-id>
- DATA <raw-bytes>
- PONG
