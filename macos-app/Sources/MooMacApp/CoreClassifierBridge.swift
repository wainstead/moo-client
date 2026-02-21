import Foundation

enum CoreBridgeError: LocalizedError {
    case binaryNotFound

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "moo-core binary not found. Set MOO_CORE_BIN or place moo-core in the app bundle."
        }
    }
}

final class CoreClassifierBridge {
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private var readSource: DispatchSourceRead?
    private let decoder = JSONDecoder()

    var onEvent: ((CoreEvent) -> Void)?
    var onError: ((String) -> Void)?

    func start() throws {
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        process.terminationHandler = { [weak self] proc in
            self?.onError?("core classifier exited with status \(proc.terminationStatus)")
        }

        let coreBin = try resolveCoreBinaryPath()

        process.executableURL = URL(fileURLWithPath: coreBin)
        try process.run()

        let fd = outputPipe.fileHandleForReading.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.readAvailableOutput()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        readSource = source
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        process.terminate()
    }

    func classify(line: String, offset: UInt64) {
        let text = "\(offset)\t\(line)\n"
        guard let data = text.data(using: .utf8) else {
            return
        }
        inputPipe.fileHandleForWriting.write(data)
    }

    private func readAvailableOutput() {
        let data = outputPipe.fileHandleForReading.availableData
        guard !data.isEmpty else {
            return
        }

        guard let text = String(data: data, encoding: .utf8) else {
            onError?("core output decode failed")
            return
        }

        for line in text.split(separator: "\n") {
            do {
                let event = try decoder.decode(CoreEvent.self, from: Data(line.utf8))
                onEvent?(event)
            } catch {
                onError?("core event decode failed: \(error.localizedDescription)")
            }
        }
    }

    private func resolveCoreBinaryPath() throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let fromEnv = env["MOO_CORE_BIN"], FileManager.default.isExecutableFile(atPath: fromEnv) {
            return fromEnv
        }
        if let bundled = Bundle.main.path(forResource: "moo-core", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        throw CoreBridgeError.binaryNotFound
    }
}
