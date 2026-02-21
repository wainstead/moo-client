import Foundation

public final class MooRelayClient {
    private let wsURL: URL
    private let stateStore: RelayStateStore
    private let session: URLSession

    private var task: URLSessionWebSocketTask?
    private var parser: RelayStreamParser

    public var onConnected: ((String) -> Void)?
    public var onRawLine: ((String, UInt64) -> Void)?
    public var onPong: (() -> Void)?
    public var onSystem: ((String) -> Void)?

    public init(
        wsURL: URL,
        stateStore: RelayStateStore,
        session: URLSession = URLSession(configuration: .default)
    ) {
        self.wsURL = wsURL
        self.stateStore = stateStore
        self.session = session
        self.parser = RelayStreamParser(initialOffset: stateStore.lastOffset)
    }

    public func connect(sendResume: Bool = true) {
        let task = session.webSocketTask(with: wsURL)
        task.resume()
        self.task = task

        send(.hello(sessionID: stateStore.sessionID))
        if sendResume {
            send(.resume(offset: stateStore.lastOffset))
        }

        receiveLoop()
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    public func sendText(_ text: String) {
        send(.send(text: text))
    }

    public func ping() {
        send(.ping)
    }

    private func send(_ command: RelayCommand) {
        task?.send(.string(command.encodeLine())) { [weak self] error in
            guard let self, let error else { return }
            self.onSystem?("send failed: \(error.localizedDescription)")
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(message):
                self.handleMessage(message)
                self.receiveLoop()
            case let .failure(error):
                self.onSystem?("connection closed: \(error.localizedDescription)")
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case let .string(text):
            handleControlText(text)
        case let .data(data):
            handleDataFrame(data)
        @unknown default:
            onSystem?("received unsupported websocket message")
        }
    }

    private func handleControlText(_ text: String) {
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            switch RelayControl.parse(line: line) {
            case let .welcome(sessionID):
                onConnected?(sessionID)
            case .pong:
                onPong?()
            case let .unknown(value):
                onSystem?("control: \(value)")
            }
        }
    }

    private func handleDataFrame(_ data: Data) {
        guard data.starts(with: Data("DATA ".utf8)) else {
            onSystem?("received non-DATA binary frame")
            return
        }

        let payload = data.dropFirst(5)
        let parsed = parser.appendDataPayload(Data(payload))
        stateStore.lastOffset = parsed.newestOffset

        for line in parsed.lines {
            onRawLine?(line.text, line.offset)
        }
    }
}
