# moo-client SPEC

Phase tracking for the relay/client system.

## Current status

- Phase 1 (Basic Relay): implemented
- Phase 2+: not started

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
