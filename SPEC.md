# moo-client SPEC

Phase tracking for the relay/client system.

## Current status

- Phase 1 (Basic Relay): implemented
- Phase 2 (Rolling Buffer): implemented
- Phase 3 (Resume Support): implemented
- Phase 4 (Core Engine): implemented
- Phase 5 (macOS UI): implemented

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

- Phase 6: LAN dev mode for proxy (`0.0.0.0` listen option) + tests
- Phase 7: iOS relay client with `HELLO`, `SEND`, `PING`, `RESUME`
- Phase 8: iOS minimal UI (occupants, messages, input)
- Phase 9: iPhone sleep/resume validation checklist and fixes

## Locked protocol

Client -> Proxy:
- HELLO <session-id>
- RESUME <offset>
- SEND <text>\n
- PING

Proxy -> Client:
- WELCOME <session-id>
- DATA <raw-bytes>
- PONG
