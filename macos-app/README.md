# macos-app

Minimal SwiftUI desktop client.

Responsibilities:
- connect to proxy websocket endpoint
- send user commands
- display occupants/messages/input UI
- consume structured events from classifier bridge

Runtime notes:
- requires reachable proxy (`ws://127.0.0.1:9000/ws` by default)
- requires `moo-core` binary (auto-discovered from env, bundle, dev path, or PATH)
