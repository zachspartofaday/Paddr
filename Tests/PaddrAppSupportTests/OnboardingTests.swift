import XCTest
@testable import PaddrAppSupport

final class OnboardingTests: XCTestCase {
    func testAbsentMarkerPresentsAutomatically() {
        XCTAssertTrue(
            OnboardingEligibility.shouldPresent(
                trigger: .automatic,
                hasRecordedDismissal: false
            )
        )
    }

    func testCompletedAndSkippedGuidesDoNotPresentAutomatically() {
        for dismissal in OnboardingDismissal.allCases {
            let defaults = isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
            let preferences = OnboardingPreferences(defaults: defaults)

            preferences.record(dismissal)

            XCTAssertEqual(preferences.dismissal, dismissal)
            XCTAssertFalse(
                OnboardingEligibility.shouldPresent(
                    trigger: .automatic,
                    hasRecordedDismissal: preferences.hasRecordedDismissal
                )
            )
        }
    }

    func testHelpPresentationAlwaysOpens() {
        for hasRecordedDismissal in [false, true] {
            XCTAssertTrue(
                OnboardingEligibility.shouldPresent(
                    trigger: .help,
                    hasRecordedDismissal: hasRecordedDismissal
                )
            )
        }
    }

    func testCompletedThenExplicitSkipRemainsCompleted() {
        assertDismissalTransition([.completed, .skipped], expected: .completed)
    }

    func testSkippedThenGetStartedUpgradesToCompleted() {
        assertDismissalTransition([.skipped, .completed], expected: .completed)
    }

    func testAbsentThenSkipRecordsSkipped() {
        assertDismissalTransition([.skipped], expected: .skipped)
    }

    func testAbsentThenGetStartedRecordsCompleted() {
        assertDismissalTransition([.completed], expected: .completed)
    }

    func testVisibleGuidePresentationFocusesInsteadOfCreatingDuplicate() {
        var presentation = OnboardingWindowPresentation()

        XCTAssertEqual(presentation.requestPresentation(), .create)
        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.requestPresentation(), .focusExisting)
        XCTAssertTrue(presentation.isVisible)
    }

    func testClosedGuidePresentationCreatesFreshWindow() {
        var presentation = OnboardingWindowPresentation()
        XCTAssertEqual(presentation.requestPresentation(), .create)

        presentation.didClose()

        XCTAssertFalse(presentation.isVisible)
        XCTAssertEqual(presentation.requestPresentation(), .create)
    }

    func testPagerAdvancesAndBacktracksWithinFourPageBounds() {
        var pager = OnboardingPager()
        XCTAssertEqual(pager.pageIndex, 0)
        XCTAssertEqual(pager.pageNumber, 1)
        XCTAssertFalse(pager.canGoBack)
        XCTAssertFalse(pager.isLastPage)

        pager.goBack()
        XCTAssertEqual(pager.pageIndex, 0)

        for expectedIndex in 1..<OnboardingPager.pageCount {
            pager.advance()
            XCTAssertEqual(pager.pageIndex, expectedIndex)
        }
        XCTAssertTrue(pager.isLastPage)

        pager.advance()
        XCTAssertEqual(pager.pageIndex, OnboardingPager.pageCount - 1)

        pager.goBack()
        XCTAssertEqual(pager.pageIndex, OnboardingPager.pageCount - 2)
        XCTAssertTrue(pager.canGoBack)
    }

    func testNewPagerResetsToWelcomePage() {
        var priorPresentationPager = OnboardingPager()
        priorPresentationPager.advance()
        priorPresentationPager.advance()
        XCTAssertEqual(priorPresentationPager.pageIndex, 2)

        let reopenedPresentationPager = OnboardingPager()

        XCTAssertEqual(reopenedPresentationPager.pageIndex, 0)
        XCTAssertEqual(reopenedPresentationPager.pageNumber, 1)
    }

    private func assertDismissalTransition(
        _ transitions: [OnboardingDismissal],
        expected: OnboardingDismissal,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let preferences = OnboardingPreferences(defaults: defaults)

        for transition in transitions { preferences.record(transition) }

        XCTAssertEqual(preferences.dismissal, expected, file: file, line: line)
        XCTAssertFalse(
            OnboardingEligibility.shouldPresent(
                trigger: .automatic,
                hasRecordedDismissal: preferences.hasRecordedDismissal
            ),
            file: file,
            line: line
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "OnboardingTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults suite")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: Self.suiteMarkerKey)
        return defaults
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        guard let suiteName = defaults.string(forKey: Self.suiteMarkerKey) else {
            XCTFail("Isolated defaults suite marker is missing")
            return ""
        }
        return suiteName
    }

    private static let suiteMarkerKey = "OnboardingTests.suiteName"
}
