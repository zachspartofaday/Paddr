import XCTest
@testable import PaddrAppSupport

final class MenuStatusTests: XCTestCase {
    func testMessageStateMapsEveryMenuStatusCase() {
        let failures: [MenuFailure] = [
            .accessibilityRequired,
            .configurationRecovered(diagnostic: "recovered"),
            .configurationLoad(diagnostic: "load"),
            .configurationInvalid(diagnostic: "invalid"),
            .configurationSave(diagnostic: "save"),
            .output(diagnostic: "output"),
            .unexpected(diagnostic: "unexpected"),
        ]
        for failure in failures {
            XCTAssertEqual(MenuStatus.failure(failure).messageState, .failure)
        }

        let guidanceStatuses: [MenuStatus] = [
            .waitingForNeutral,
            .defaultsRestored,
            .requestingAccessibility,
            .accessibilitySettings,
        ]
        for status in guidanceStatuses {
            XCTAssertEqual(status.messageState, .guidance)
        }

        let hiddenStatuses: [MenuStatus] = [
            .off,
            .waitingForController,
            .connecting,
            .active,
            .configurationSaved,
            .releasingOutputs,
            .stopped,
        ]
        for status in hiddenStatuses {
            XCTAssertNil(status.messageState)
        }
    }

    func testEveryFailureMessageIncludesItsRecoveryAction() {
        let messages: [(MenuFailure, String)] = [
            (.accessibilityRequired, "Enable Paddr in Accessibility, then turn Trackpad Output on again."),
            (.configurationRecovered(diagnostic: "recovered"), "Paddr repaired the saved profile selection. Review the profiles, then choose Save & Apply."),
            (.configurationLoad(diagnostic: "load"), "Saved settings couldn’t be loaded. Repair or move ~/.config/Paddr/config.json, then reopen Paddr."),
            (.configurationInvalid(diagnostic: "invalid"), "Some settings are invalid. Review the values, then choose Save & Apply again."),
            (.configurationSave(diagnostic: "save"), "Settings couldn’t be saved. Your edits are still available. Choose Save & Apply to try again."),
            (.output(diagnostic: "output"), "Trackpad output stopped because of an error. Check the puck and controller, then turn Trackpad Output on again."),
            (.unexpected(diagnostic: "unexpected"), "An unexpected error occurred. Reopen Paddr, then try again."),
        ]

        for (failure, expected) in messages {
            XCTAssertEqual(String(localized: failure.message), expected)
        }
    }
}
