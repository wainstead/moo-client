import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let speaker: String
    let message: String
    let offset: UInt64
}

struct SystemMessage: Identifiable {
    let id = UUID()
    let text: String
    let offset: UInt64
}

enum CoreEvent: Decodable {
    case chat(speaker: String, message: String, offset: UInt64)
    case arrive(who: String, offset: UInt64)
    case leave(who: String, offset: UInt64)
    case system(text: String, offset: UInt64)

    private enum CodingKeys: String, CodingKey {
        case kind
        case speaker
        case message
        case who
        case text
        case offset
    }

    private enum Kind: String, Decodable {
        case chat
        case arrive
        case leave
        case system
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let offset = try container.decode(UInt64.self, forKey: .offset)
        switch kind {
        case .chat:
            self = .chat(
                speaker: try container.decode(String.self, forKey: .speaker),
                message: try container.decode(String.self, forKey: .message),
                offset: offset
            )
        case .arrive:
            self = .arrive(
                who: try container.decode(String.self, forKey: .who),
                offset: offset
            )
        case .leave:
            self = .leave(
                who: try container.decode(String.self, forKey: .who),
                offset: offset
            )
        case .system:
            self = .system(
                text: try container.decode(String.self, forKey: .text),
                offset: offset
            )
        }
    }
}
