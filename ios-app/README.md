# ios-app

Swift package for iOS-side client components.

Targets:
- `MooIOSRelay`: websocket/protocol client (`HELLO`, `RESUME`, `RESUME_LIVE`, `SEND`, `PING`)
- `MooIOSCore`: structured event classification on iOS side
- `MooIOSUI`: minimal SwiftUI view model + chat UI
- `MooIOSRelaySelfTest`: executable smoke checks for relay/parser behavior
- `MooIOSCoreFixtureRunner`: executable for shared classifier fixture parity checks

This package provides reusable modules. The minimal checked-in physical-device
host app for Phase 9 acceptance lives at `../ios-host-app/Phase9Host.xcodeproj`.
