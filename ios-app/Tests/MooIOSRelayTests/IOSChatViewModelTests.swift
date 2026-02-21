import Foundation
import MooIOSCore
import MooIOSUI

#if canImport(XCTest)
import XCTest

@MainActor
final class IOSChatViewModelTests: XCTestCase {
    func testApplyArriveAndLeaveUpdatesOccupants() {
        let vm = IOSChatViewModel()

        vm.apply(.arrive(who: "Wizard", offset: 1))
        XCTAssertEqual(vm.occupants, ["Wizard"])

        vm.apply(.leave(who: "Wizard", offset: 2))
        XCTAssertEqual(vm.occupants, [])
    }

    func testApplyChatAppendsMessages() {
        let vm = IOSChatViewModel()

        vm.apply(.chat(speaker: "Frog", message: "hello", offset: 7))

        XCTAssertEqual(vm.chatMessages.count, 1)
        XCTAssertEqual(vm.chatMessages[0].speaker, "Frog")
        XCTAssertEqual(vm.chatMessages[0].message, "hello")
        XCTAssertEqual(vm.chatMessages[0].offset, 7)
    }
}
#endif
