import Foundation

enum Phase9HostConfig {
    // For a physical iPhone Phase 9 run, edit this to ws://<laptop-lan-ip>:9000/ws.
    static let defaultWebSocketURLString = "ws://127.0.0.1:9000/ws"
    static let stateNamespace = "moo.phase9.host"

    static var webSocketURL: URL {
        guard let url = URL(string: defaultWebSocketURLString) else {
            preconditionFailure("Invalid Phase 9 WebSocket URL: \(defaultWebSocketURLString)")
        }
        return url
    }
}
