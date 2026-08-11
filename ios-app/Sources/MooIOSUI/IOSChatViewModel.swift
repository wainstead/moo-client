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

public struct IOSRelayDebugEvent: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let text: String
    public let offset: UInt64
}

@MainActor
public final class IOSChatViewModel: ObservableObject {
    @Published public private(set) var occupants: [String] = []
    @Published public private(set) var chatMessages: [IOSChatMessage] = []
    @Published public private(set) var systemMessages: [IOSSystemMessage] = []
    @Published public private(set) var debugEvents: [IOSRelayDebugEvent] = []
    @Published public private(set) var currentOffset: UInt64 = 0
    @Published public var inputText: String = ""
    @Published public private(set) var isConnected: Bool = false

    private var relay: MooRelayClient?

    public init() {}

    public func connect(wsURL: URL, stateStore: RelayStateStore = UserDefaultsRelayStateStore()) {
        currentOffset = stateStore.lastOffset
        guard relay == nil else {
            appendDebug("connect skipped: relay already active", offset: stateStore.lastOffset)
            return
        }

        let client = MooRelayClient(wsURL: wsURL, stateStore: stateStore)
        client.onConnected = { [weak self, weak client] sessionID in
            Task { @MainActor in
                guard let self, let client, self.relay === client else { return }
                self.isConnected = true
                self.currentOffset = stateStore.lastOffset
                self.appendDebug("WELCOME \(sessionID)", offset: stateStore.lastOffset)
                self.systemMessages.append(IOSSystemMessage(text: "WELCOME \(sessionID)", offset: stateStore.lastOffset))
            }
        }
        client.onSystem = { [weak self, weak client] text in
            Task { @MainActor in
                guard let self, let client, self.relay === client else { return }
                self.currentOffset = stateStore.lastOffset
                self.appendDebug(text, offset: stateStore.lastOffset)
                self.systemMessages.append(IOSSystemMessage(text: text, offset: stateStore.lastOffset))
                if text.hasPrefix("connection closed") {
                    self.isConnected = false
                    self.relay = nil
                }
            }
        }
        client.onRawLine = { [weak self, weak client] line, offset in
            let event = CoreEventClassifier.classify(line: line, offset: offset)
            Task { @MainActor in
                guard let self, let client, self.relay === client else { return }
                self.currentOffset = offset
                self.appendDebug("DATA offset=\(offset) \(line)", offset: offset)
                self.apply(event)
            }
        }

        relay = client
        appendDebug("connecting to \(wsURL.absoluteString)", offset: stateStore.lastOffset)
        appendDebug("HELLO \(stateStore.sessionID)", offset: stateStore.lastOffset)
        appendDebug("RESUME \(stateStore.lastOffset)", offset: stateStore.lastOffset)
        systemMessages.append(IOSSystemMessage(text: "connecting to \(wsURL.absoluteString)", offset: stateStore.lastOffset))
        client.connect(sendResume: true)
    }

    public func disconnect() {
        appendDebug("disconnect requested", offset: currentOffset)
        relay?.disconnect()
        relay = nil
        isConnected = false
    }

    public func reconnect(wsURL: URL, stateStore: RelayStateStore = UserDefaultsRelayStateStore()) {
        appendDebug("reconnect requested", offset: stateStore.lastOffset)
        disconnect()
        connect(wsURL: wsURL, stateStore: stateStore)
    }

    public func sendInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appendDebug("SEND \(text)", offset: currentOffset)
        relay?.sendText(text)
        inputText = ""
    }

    public func ping() {
        appendDebug("PING", offset: currentOffset)
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

    private func appendDebug(_ text: String, offset: UInt64) {
        debugEvents.append(IOSRelayDebugEvent(timestamp: Date(), text: text, offset: offset))
        if debugEvents.count > 300 {
            debugEvents.removeFirst(debugEvents.count - 300)
        }
    }
}
