import Foundation
import MooIOSCore

private struct Fixture: Decodable {
    let line: String
    let offset: UInt64
}

@main
struct MooIOSCoreFixtureRunner {
    static func main() {
        let fixturePath = CommandLine.arguments.dropFirst().first ?? "../fixtures/classifier_fixtures.jsonl"
        let fixtureURL = URL(fileURLWithPath: fixturePath)

        let input: String
        do {
            input = try String(contentsOf: fixtureURL, encoding: .utf8)
        } catch {
            fputs("failed to read fixture file \(fixturePath): \(error)\n", stderr)
            exit(1)
        }

        for (idx, raw) in input.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let data = Data(raw.utf8)
            let fixture: Fixture
            do {
                fixture = try JSONDecoder().decode(Fixture.self, from: data)
            } catch {
                fputs("invalid fixture JSON at line \(idx + 1): \(error)\n", stderr)
                exit(1)
            }

            let event = CoreEventClassifier.classify(line: fixture.line, offset: fixture.offset)
            print(normalize(index: idx, event: event))
        }
    }

    private static func normalize(index: Int, event: CoreEvent) -> String {
        switch event {
        case .chat(let speaker, let message, let offset):
            return "\(index)|chat|\(offset)|\(speaker)|\(message)"
        case .arrive(let who, let offset):
            return "\(index)|arrive|\(offset)|\(who)"
        case .leave(let who, let offset):
            return "\(index)|leave|\(offset)|\(who)"
        case .system(let text, let offset):
            return "\(index)|system|\(offset)|\(text)"
        }
    }
}
