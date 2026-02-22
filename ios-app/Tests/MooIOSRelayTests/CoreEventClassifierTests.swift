import Foundation
import MooIOSCore

#if canImport(XCTest)
import XCTest

final class CoreEventClassifierTests: XCTestCase {
    func testClassifiesChat() {
        let event = CoreEventClassifier.classify(line: "Frog: hello", offset: 11)
        XCTAssertEqual(event, .chat(speaker: "Frog", message: "hello", offset: 11))
    }

    func testClassifiesArrive() {
        let event = CoreEventClassifier.classify(line: "Wizard has arrived.", offset: 42)
        XCTAssertEqual(event, .arrive(who: "Wizard", offset: 42))
    }

    func testClassifiesLeave() {
        let event = CoreEventClassifier.classify(line: "Guest has left.", offset: 99)
        XCTAssertEqual(event, .leave(who: "Guest", offset: 99))
    }

    func testClassifiesSystem() {
        let event = CoreEventClassifier.classify(line: "*** system message ***", offset: 5)
        XCTAssertEqual(event, .system(text: "*** system message ***", offset: 5))
    }

    func testNoSpaceAfterColonIsSystem() {
        let event = CoreEventClassifier.classify(line: "Frog:hello", offset: 7)
        XCTAssertEqual(event, .system(text: "Frog:hello", offset: 7))
    }

    func testTrailingSpaceAfterChatPrefixIsChatWithEmptyMessage() {
        let event = CoreEventClassifier.classify(line: "Frog:   ", offset: 8)
        XCTAssertEqual(event, .chat(speaker: "Frog", message: "", offset: 8))
    }
}
#endif
