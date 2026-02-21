import Foundation

final class RelayClient {
    private let wsURL: URL
    private let sessionID: String
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var classifier = CoreClassifierBridge()

    private var receiveBuffer = Data()
    private(set) var upstreamOffset: UInt64 = 0

    var onEvent: ((CoreEvent) -> Void)?
    var onSystem: ((String) -> Void)?

    init(wsURL: URL, sessionID: String = UUID().uuidString) {
        self.wsURL = wsURL
        self.sessionID = sessionID
    }

    func connect(resumeOffset: UInt64?) {
        classifier.onEvent = { [weak self] event in
            self?.onEvent?(event)
        }
        classifier.onError = { [weak self] message in
            self?.onSystem?(message)
        }

        do {
            try classifier.start()
        } catch {
            onSystem?("failed to start core classifier: \(error.localizedDescription)")
            return
        }

        task = session.webSocketTask(with: wsURL)
        task?.resume()

        send(line: "HELLO \(sessionID)")
        if let offset = resumeOffset {
            send(line: "RESUME \(offset)")
        }

        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        classifier.stop()
    }

    func sendText(_ text: String) {
        send(line: "SEND \(text)")
    }

    private func send(line: String) {
        task?.send(.string(line + "\n")) { [weak self] error in
            if let error {
                self?.onSystem?("send failed: \(error.localizedDescription)")
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveLoop()
            case .failure(let error):
                self.onSystem?("connection closed: \(error.localizedDescription)")
                self.classifier.stop()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            for line in text.split(separator: "\n") {
                if line == "PONG" {
                    continue
                }
                if line.hasPrefix("WELCOME ") {
                    onSystem?(String(line))
                }
            }
        case .data(let data):
            guard data.starts(with: Data("DATA ".utf8)) else {
                return
            }
            let payload = data.dropFirst(5)
            processUpstreamBytes(Data(payload))
        @unknown default:
            break
        }
    }

    private func processUpstreamBytes(_ data: Data) {
        receiveBuffer.append(data)

        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer.prefix(upTo: newlineIndex)
            receiveBuffer.removeSubrange(...newlineIndex)

            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }
            let offsetForLine = upstreamOffset + UInt64(lineData.count)
            upstreamOffset += UInt64(lineData.count + 1)
            classifier.classify(line: line, offset: offsetForLine)
        }
    }
}
