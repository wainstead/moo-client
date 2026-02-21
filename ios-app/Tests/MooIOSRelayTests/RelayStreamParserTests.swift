import Foundation
@testable import MooIOSRelay

#if canImport(XCTest)
import XCTest

final class RelayStreamParserTests: XCTestCase {

    func testSingleLineInOnePayload() {
        let parser = RelayStreamParser(initialOffset: 0)
        let chunk = parser.appendDataPayload(Data("hello\n".utf8))
        XCTAssertEqual(chunk.lines.count, 1)
        XCTAssertEqual(chunk.lines[0].text, "hello")
        XCTAssertEqual(chunk.lines[0].offset, 6)
        XCTAssertEqual(chunk.newestOffset, 6)
    }

    func testTwoLinesInOnePayload() {
        let parser = RelayStreamParser(initialOffset: 0)
        let chunk = parser.appendDataPayload(Data("a\nb\n".utf8))
        XCTAssertEqual(chunk.lines.count, 2)
        XCTAssertEqual(chunk.lines[0].text, "a")
        XCTAssertEqual(chunk.lines[0].offset, 2)
        XCTAssertEqual(chunk.lines[1].text, "b")
        XCTAssertEqual(chunk.lines[1].offset, 4)
        XCTAssertEqual(chunk.newestOffset, 4)
    }

    func testPartialLineNoEmit() {
        let parser = RelayStreamParser(initialOffset: 0)
        let chunk = parser.appendDataPayload(Data("no newline yet".utf8))
        XCTAssertEqual(chunk.lines.count, 0)
        XCTAssertEqual(chunk.newestOffset, 0)
    }

    func testSecondPayloadCompletesLine() {
        let parser = RelayStreamParser(initialOffset: 0)
        _ = parser.appendDataPayload(Data("prefix ".utf8))
        let chunk = parser.appendDataPayload(Data("suffix\n".utf8))
        XCTAssertEqual(chunk.lines.count, 1)
        XCTAssertEqual(chunk.lines[0].text, "prefix suffix")
        XCTAssertEqual(chunk.lines[0].offset, 14)
        XCTAssertEqual(chunk.newestOffset, 14)
    }

    func testInitialOffsetCarried() {
        let parser = RelayStreamParser(initialOffset: 100)
        let chunk = parser.appendDataPayload(Data("x\n".utf8))
        XCTAssertEqual(chunk.lines[0].offset, 102)
        XCTAssertEqual(chunk.newestOffset, 102)
    }

    func testEmptyPayloadNoChange() {
        let parser = RelayStreamParser(initialOffset: 5)
        let chunk = parser.appendDataPayload(Data())
        XCTAssertEqual(chunk.lines.count, 0)
        XCTAssertEqual(chunk.newestOffset, 5)
    }
}
#endif
