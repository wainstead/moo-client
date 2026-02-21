import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var occupants: [String] = []
    @Published var chats: [ChatMessage] = []
    @Published var systems: [SystemMessage] = []
    @Published var input: String = ""

    private var relay: RelayClient?

    func connect() {
        guard relay == nil else { return }
        guard let wsURL = URL(string: ProcessInfo.processInfo.environment["MOO_WS_URL"] ?? "ws://127.0.0.1:9000/ws") else {
            systems.append(SystemMessage(text: "invalid MOO_WS_URL", offset: 0))
            return
        }

        let client = RelayClient(wsURL: wsURL)
        client.onSystem = { [weak self] text in
            Task { @MainActor in
                self?.systems.append(SystemMessage(text: text, offset: client.upstreamOffset))
            }
        }
        client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.apply(event)
            }
        }
        client.onDisconnected = { [weak self] in
            Task { @MainActor in
                self?.systems.append(SystemMessage(text: "relay disconnected", offset: client.upstreamOffset))
                self?.relay = nil
            }
        }

        relay = client
        systems.append(SystemMessage(text: "connecting to \(wsURL.absoluteString)", offset: 0))
        client.connect(resumeOffset: nil)
    }

    func disconnect() {
        relay?.disconnect()
        relay = nil
    }

    func sendInput() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        relay?.sendText(trimmed)
        input = ""
    }

    private func apply(_ event: CoreEvent) {
        switch event {
        case let .chat(speaker, message, offset):
            chats.append(ChatMessage(speaker: speaker, message: message, offset: offset))
        case let .arrive(who, offset):
            if !occupants.contains(who) {
                occupants.append(who)
                occupants.sort()
            }
            systems.append(SystemMessage(text: "\(who) arrived", offset: offset))
        case let .leave(who, offset):
            occupants.removeAll { $0 == who }
            systems.append(SystemMessage(text: "\(who) left", offset: offset))
        case let .system(text, offset):
            systems.append(SystemMessage(text: text, offset: offset))
        }
    }
}
