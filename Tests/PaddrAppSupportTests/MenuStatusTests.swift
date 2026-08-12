import XCTest
@testable import PaddrAppSupport

final class MenuStatusTests: XCTestCase {
    func testMessageStateMapsEveryMenuStatusCase() {
        let failures: [MenuFailure] = [
            .inputMonitoringRequired,
            .accessibilityRequired,
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
            .defaultsRestored,
            .requestingInputMonitoring,
            .requestingAccessibility,
            .inputMonitoringSettings,
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
}
