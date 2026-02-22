import Foundation
import MooIOSCore

#if canImport(XCTest)
import XCTest

final class CoreEventFixtureTests: XCTestCase {
    func testSharedClassifierFixtures() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/classifier_fixtures.jsonl")

        let input = try String(contentsOf: fixtureURL, encoding: .utf8)
        let decoder = JSONDecoder()

        for (idx, raw) in input.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let fixture = try decoder.decode(Fixture.self, from: Data(raw.utf8))
            let got = CoreEventClassifier.classify(line: fixture.line, offset: fixture.offset)
            XCTAssertEqual(
                normalize(got),
                fixture.expected,
                "fixture mismatch at line \(idx + 1) for input: \(fixture.line)"
            )
        }
    }

    private func normalize(_ event: CoreEvent) -> ExpectedEvent {
        switch event {
        case .chat(let speaker, let message, let offset):
            return .chat(speaker: speaker, message: message, offset: offset)
        case .arrive(let who, let offset):
            return .arrive(who: who, offset: offset)
        case .leave(let who, let offset):
            return .leave(who: who, offset: offset)
        case .system(let text, let offset):
            return .system(text: text, offset: offset)
        }
    }
}

private struct Fixture: Decodable {
    let line: String
    let offset: UInt64
    let expected: ExpectedEvent
}

private enum ExpectedEvent: Equatable, Decodable {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)

        switch kind {
        case "chat":
            self = .chat(
                speaker: try container.decode(String.self, forKey: .speaker),
                message: try container.decode(String.self, forKey: .message),
                offset: try container.decode(UInt64.self, forKey: .offset)
            )
        case "arrive":
            self = .arrive(
                who: try container.decode(String.self, forKey: .who),
                offset: try container.decode(UInt64.self, forKey: .offset)
            )
        case "leave":
            self = .leave(
                who: try container.decode(String.self, forKey: .who),
                offset: try container.decode(UInt64.self, forKey: .offset)
            )
        case "system":
            self = .system(
                text: try container.decode(String.self, forKey: .text),
                offset: try container.decode(UInt64.self, forKey: .offset)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "unknown kind: \(kind)"
            )
        }
    }
}
#endif
