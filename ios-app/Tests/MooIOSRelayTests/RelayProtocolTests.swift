import Foundation
@testable import MooIOSRelay

#if canImport(XCTest)
import XCTest

final class RelayProtocolTests: XCTestCase {

    func testRelayCommandEncodeHello() {
        let cmd = RelayCommand.hello(sessionID: "abc-123")
        XCTAssertEqual(cmd.encodeLine(), "HELLO abc-123\n")
    }

    func testRelayCommandEncodeResume() {
        let cmd = RelayCommand.resume(offset: 4096)
        XCTAssertEqual(cmd.encodeLine(), "RESUME 4096\n")
    }

    func testRelayCommandEncodeSend() {
        let cmd = RelayCommand.send(text: "look")
        XCTAssertEqual(cmd.encodeLine(), "SEND look\n")
    }

    func testRelayCommandEncodePing() {
        let cmd = RelayCommand.ping
        XCTAssertEqual(cmd.encodeLine(), "PING\n")
    }

    func testRelayControlParseWelcome() {
        let got = RelayControl.parse(line: "WELCOME session-xyz")
        if case let .welcome(sessionID) = got {
            XCTAssertEqual(sessionID, "session-xyz")
        } else {
            XCTFail("expected .welcome, got \(got)")
        }
    }

    func testRelayControlParsePong() {
        let got = RelayControl.parse(line: "PONG")
        if case .pong = got { } else {
            XCTFail("expected .pong, got \(got)")
        }
    }

    func testRelayControlParseResumed() {
        let got = RelayControl.parse(line: "RESUMED 42")
        if case let .resumed(offset) = got {
            XCTAssertEqual(offset, 42)
        } else {
            XCTFail("expected .resumed, got \(got)")
        }
    }

    func testRelayControlParseUnknown() {
        let got = RelayControl.parse(line: "DATA something")
        if case let .unknown(line) = got {
            XCTAssertEqual(line, "DATA something")
        } else {
            XCTFail("expected .unknown, got \(got)")
        }
    }
}
#endif
