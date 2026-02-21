import Foundation

public struct ParsedDataChunk: Equatable {
    public let lines: [ParsedLine]
    public let newestOffset: UInt64
}

public struct ParsedLine: Equatable {
    public let text: String
    public let offset: UInt64

    public init(text: String, offset: UInt64) {
        self.text = text
        self.offset = offset
    }
}

public final class RelayStreamParser {
    private var receiveBuffer = Data()
    private(set) public var currentOffset: UInt64

    public init(initialOffset: UInt64) {
        self.currentOffset = initialOffset
    }

    public func appendDataPayload(_ payload: Data) -> ParsedDataChunk {
        receiveBuffer.append(payload)

        var lines: [ParsedLine] = []

        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer.prefix(upTo: newlineIndex)
            receiveBuffer.removeSubrange(...newlineIndex)

            currentOffset += UInt64(lineData.count + 1)

            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(ParsedLine(text: line, offset: currentOffset))
            }
        }

        return ParsedDataChunk(lines: lines, newestOffset: currentOffset)
    }
}
