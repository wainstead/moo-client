# ios-app

Swift package for iOS-side client components.

Targets:
- `MooIOSRelay`: websocket/protocol client (`HELLO`, `RESUME`, `SEND`, `PING`)
- `MooIOSCore`: structured event classification on iOS side
- `MooIOSUI`: minimal SwiftUI view model + chat UI
- `MooIOSRelaySelfTest`: executable smoke checks for relay/parser behavior

This package currently provides reusable modules. A standalone iOS host app target is not yet in-repo.
