# proxy

Go relay between LambdaMOO TCP and client WebSocket connections.

Key behavior:
- single upstream TCP session to MOO
- multiple WebSocket clients
- rolling 1 MB buffer for replay
- explicit resume by byte offset (`RESUME <offset>`) or live boundary (`RESUME_LIVE`)

Main entrypoint:
- `cmd/mooproxy`

Important internals:
- `internal/relay.go`
- `internal/ring_buffer.go`
- `internal/ws.go`
