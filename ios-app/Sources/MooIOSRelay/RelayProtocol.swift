import Foundation

public enum RelayCommand: Equatable {
    case hello(sessionID: String)
    case resume(offset: UInt64)
    case send(text: String)
    case ping

    public func encodeLine() -> String {
        switch self {
        case let .hello(sessionID):
            return "HELLO \(sessionID)\n"
        case let .resume(offset):
            return "RESUME \(offset)\n"
        case let .send(text):
            return "SEND \(text)\n"
        case .ping:
            return "PING\n"
        }
    }
}

public enum RelayControl: Equatable {
    case welcome(sessionID: String)
    case pong
    case unknown(line: String)

    public static func parse(line: String) -> RelayControl {
        if line.hasPrefix("WELCOME ") {
            return .welcome(sessionID: String(line.dropFirst("WELCOME ".count)))
        }
        if line == "PONG" {
            return .pong
        }
        return .unknown(line: line)
    }
}
