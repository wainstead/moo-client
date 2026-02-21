import Foundation
import MooIOSRelay

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("self-test failed: \(message)\n", stderr)
        exit(1)
    }
}

func run() {
    check(RelayCommand.hello(sessionID: "abc").encodeLine() == "HELLO abc\n", "hello encoding")
    check(RelayCommand.resume(offset: 42).encodeLine() == "RESUME 42\n", "resume encoding")
    check(RelayCommand.send(text: "look").encodeLine() == "SEND look\n", "send encoding")
    check(RelayCommand.ping.encodeLine() == "PING\n", "ping encoding")

    check(RelayControl.parse(line: "WELCOME sid-1") == .welcome(sessionID: "sid-1"), "welcome parse")
    check(RelayControl.parse(line: "PONG") == .pong, "pong parse")

    let parser = RelayStreamParser(initialOffset: 0)
    let first = parser.appendDataPayload(Data("hello".utf8))
    check(first.lines.isEmpty, "partial chunk should emit no lines")
    check(first.newestOffset == 0, "partial chunk offset")

    let second = parser.appendDataPayload(Data(" world\nnext line\n".utf8))
    check(
        second.lines == [
            ParsedLine(text: "hello world", offset: 12),
            ParsedLine(text: "next line", offset: 22),
        ],
        "chunk parse lines"
    )
    check(second.newestOffset == 22, "chunk parse offset")

    let resumed = RelayStreamParser(initialOffset: 100).appendDataPayload(Data("a\n".utf8))
    check(resumed.newestOffset == 102, "resume offset")

    print("MooIOSRelay self-test passed")
}

run()
