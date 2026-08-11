# Phase9Host

Minimal in-repo iPhone host app for Phase 9 sleep/resume acceptance.

The app imports the local `../ios-app` Swift package, owns an `IOSChatViewModel`, presents `IOSChatView`, persists relay state with `UserDefaultsRelayStateStore`, and reconnects when the scene becomes active.

Before a physical iPhone run, edit `Phase9Host/Phase9HostConfig.swift`:

```swift
static let defaultWebSocketURLString = "ws://<laptop-lan-ip>:9000/ws"
```

Keep the iPhone on the same trusted LAN as the laptop proxy. The default remains `ws://127.0.0.1:9000/ws` so simulator/local edits are safe by default.
