import Foundation
import Combine
import MooIOSCore
import MooIOSRelay

public struct IOSChatMessage: Identifiable, Equatable {
    public let id = UUID()
    public let speaker: String
    public let message: String
    public let offset: UInt64
}

public struct IOSSystemMessage: Identifiable, Equatable {
    public let id = UUID()
    public let text: String
    public let offset: UInt64
}

@MainActor
public final class IOSChatViewModel: ObservableObject {
    @Published public private(set) var occupants: [String] = []
    @Published public private(set) var chatMessages: [IOSChatMessage] = []
    @Published public private(set) var systemMessages: [IOSSystemMessage] = []
    @Published public var inputText: String = ""
    @Published public private(set) var isConnected: Bool = false

    private var relay: MooRelayClient?

    public init() {}

    public func connect(wsURL: URL, stateStore: RelayStateStore = UserDefaultsRelayStateStore()) {
        guard relay == nil else { return }

        let client = MooRelayClient(wsURL: wsURL, stateStore: stateStore)
        client.onConnected = { [weak self] sessionID in
            Task { @MainActor in
                self?.isConnected = true
                self?.systemMessages.append(IOSSystemMessage(text: "WELCOME \(sessionID)", offset: stateStore.lastOffset))
            }
        }
        client.onSystem = { [weak self] text in
            Task { @MainActor in
                self?.systemMessages.append(IOSSystemMessage(text: text, offset: stateStore.lastOffset))
                if text.hasPrefix("connection closed") {
                    self?.isConnected = false
                    self?.relay = nil
                }
            }
        }
        client.onRawLine = { [weak self] line, offset in
            let event = CoreEventClassifier.classify(line: line, offset: offset)
            Task { @MainActor in
                self?.apply(event)
            }
        }

        relay = client
        systemMessages.append(IOSSystemMessage(text: "connecting to \(wsURL.absoluteString)", offset: stateStore.lastOffset))
        client.connect(sendResume: true)
    }

    public func disconnect() {
        relay?.disconnect()
        relay = nil
        isConnected = false
    }

    public func sendInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        relay?.sendText(text)
        inputText = ""
    }

    public func ping() {
        relay?.ping()
    }

    public func apply(_ event: CoreEvent) {
        switch event {
        case let .chat(speaker, message, offset):
            chatMessages.append(IOSChatMessage(speaker: speaker, message: message, offset: offset))
        case let .arrive(who, offset):
            if !occupants.contains(who) {
                occupants.append(who)
                occupants.sort()
            }
            systemMessages.append(IOSSystemMessage(text: "\(who) arrived", offset: offset))
        case let .leave(who, offset):
            occupants.removeAll { $0 == who }
            systemMessages.append(IOSSystemMessage(text: "\(who) left", offset: offset))
        case let .system(text, offset):
            systemMessages.append(IOSSystemMessage(text: text, offset: offset))
        }
    }
}
