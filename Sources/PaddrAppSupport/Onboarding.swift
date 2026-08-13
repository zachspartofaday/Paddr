import Foundation

package enum OnboardingPresentationTrigger: Sendable {
    case automatic
    case help
}

package enum OnboardingDismissal: String, CaseIterable, Sendable {
    case skipped
    case completed
}

package enum OnboardingEligibility {
    package static func shouldPresent(
        trigger: OnboardingPresentationTrigger,
        hasRecordedDismissal: Bool
    ) -> Bool {
        switch trigger {
        case .automatic:
            !hasRecordedDismissal
        case .help:
            true
        }
    }
}

package final class OnboardingPreferences {
    package static let dismissalKey = "com.partofaday.Paddr.onboarding.v1.dismissal"

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package var dismissal: OnboardingDismissal? {
        guard let rawValue = defaults.string(forKey: Self.dismissalKey) else { return nil }
        return OnboardingDismissal(rawValue: rawValue)
    }

    package var hasRecordedDismissal: Bool { dismissal != nil }

    package func record(_ dismissal: OnboardingDismissal) {
        guard self.dismissal != .completed else { return }
        defaults.set(dismissal.rawValue, forKey: Self.dismissalKey)
    }
}

package enum OnboardingWindowAction: Equatable, Sendable {
    case create
    case focusExisting
}

package struct OnboardingWindowPresentation: Equatable, Sendable {
    package private(set) var isVisible = false

    package init() {}

    package mutating func requestPresentation() -> OnboardingWindowAction {
        guard !isVisible else { return .focusExisting }
        isVisible = true
        return .create
    }

    package mutating func didClose() {
        isVisible = false
    }
}

package struct CompanionWindowState: Equatable, Sendable {
    package let isVisible: Bool
    package let isMiniaturized: Bool

    package init(isVisible: Bool, isMiniaturized: Bool) {
        self.isVisible = isVisible
        self.isMiniaturized = isMiniaturized
    }

    package var requiresRegularActivation: Bool {
        isVisible || isMiniaturized
    }
}

package struct OnboardingPager: Equatable, Sendable {
    package static let pageCount = 4

    package private(set) var pageIndex = 0

    package init() {}

    package var pageNumber: Int { pageIndex + 1 }
    package var canGoBack: Bool { pageIndex > 0 }
    package var isLastPage: Bool { pageIndex == Self.pageCount - 1 }

    package mutating func advance() {
        pageIndex = min(pageIndex + 1, Self.pageCount - 1)
    }

    package mutating func goBack() {
        pageIndex = max(pageIndex - 1, 0)
    }
}
