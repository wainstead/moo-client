import Foundation

public enum CoreEvent: Equatable {
    case chat(speaker: String, message: String, offset: UInt64)
    case arrive(who: String, offset: UInt64)
    case leave(who: String, offset: UInt64)
    case system(text: String, offset: UInt64)
}

public enum CoreEventClassifier {
    public static func classify(line: String, offset: UInt64) -> CoreEvent {
        if let chat = parseChat(line: line) {
            return .chat(speaker: chat.speaker, message: chat.message, offset: offset)
        }

        if line.hasSuffix(" has arrived.") {
            let who = String(line.dropLast(" has arrived.".count)).trimmingCharacters(in: .whitespaces)
            if !who.isEmpty {
                return .arrive(who: who, offset: offset)
            }
        }

        if line.hasSuffix(" has left.") {
            let who = String(line.dropLast(" has left.".count)).trimmingCharacters(in: .whitespaces)
            if !who.isEmpty {
                return .leave(who: who, offset: offset)
            }
        }

        return .system(text: line, offset: offset)
    }

    private static func parseChat(line: String) -> (speaker: String, message: String)? {
        guard let idx = line.firstIndex(of: ":") else {
            return nil
        }

        let speaker = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
        let msgStart = line.index(after: idx)
        let message = String(line[msgStart...]).trimmingCharacters(in: .whitespaces)

        guard !speaker.isEmpty, !message.isEmpty else {
            return nil
        }

        return (speaker, message)
    }
}
