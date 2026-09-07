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
            .profileInvalid(diagnostic: "profile invalid"),
            .profileSave(diagnostic: "profile save"),
            .output(diagnostic: "output"),
            .terminationRelease(diagnostic: "termination release"),
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
            (.accessibilityRequired, "Enable Paddr in Accessibility, then turn Mapped output on again."),
            (.configurationRecovered(diagnostic: "recovered"), "Paddr repaired the saved profile selection. Review the profiles, then choose Save & Apply."),
            (.configurationLoad(diagnostic: "load"), "Saved settings couldn’t be loaded. Repair or move the existing configuration file in ~/.config/Paddr, ~/.config/PuckPads, ~/.config/TracksBack, or ~/.config/TrackIsBack, then reopen Paddr."),
            (.configurationInvalid(diagnostic: "invalid"), "Some settings are invalid. Review the values, then choose Save & Apply again."),
            (.configurationSave(diagnostic: "save"), "Settings couldn’t be saved. Your edits are still available. Try saving again."),
            (.profileInvalid(diagnostic: "profile invalid"), "Profile change couldn’t be completed. Review the profile details, then try again."),
            (.profileSave(diagnostic: "profile save"), "Profile change couldn’t be saved. Make the change again. If it still fails, reopen Paddr."),
            (.output(diagnostic: "output"), "Mapped output stopped because of an error. Check the puck and controller, then turn Mapped output on again."),
            (.terminationRelease(diagnostic: "termination release"), "Paddr couldn’t finish releasing mapped input. Quit Paddr again to retry cleanup."),
            (.unexpected(diagnostic: "unexpected"), "An unexpected error occurred. Reopen Paddr, then try again."),
        ]

        for (failure, expected) in messages {
            XCTAssertEqual(String(localized: failure.message), expected)
        }
    }
}
