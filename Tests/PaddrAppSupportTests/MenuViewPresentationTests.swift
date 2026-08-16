import AppKit
import Dispatch
import SwiftUI
import XCTest

import PaddrAppSupport
@testable import TrackIsBackMenu
import TrackIsBackCore

@MainActor
final class MenuViewPresentationTests: XCTestCase {
    func testAccessibilityOnboardingPageFitsCompactWindowWithoutScrolling() throws {
        var pager = OnboardingPager()
        pager.advance()
        pager.advance()
        let model = PaddrMenuModel(dependencies: dependencies(store: BlockingProfileStore()))
        let view = OnboardingGuideView(
            model: model,
            onSkip: {},
            onComplete: {},
            initialPager: pager
        )
        XCTAssertEqual(PaddrStyle.guideWindowSize, NSSize(width: 680, height: 430))
        XCTAssertEqual(PaddrStyle.minimumGuideWindowSize, NSSize(width: 560, height: 430))

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.guideWindowSize)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.fittingSize.height,
            PaddrStyle.guideWindowSize.height,
            accuracy: 0.5
        )
        let scrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hostingView))
        let documentView = try XCTUnwrap(scrollView.documentView)
        documentView.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(documentView.fittingSize.height, scrollView.contentSize.height + 0.5)
    }

    func testPadConfigurationCardUsesFixedExpandedAndIntrinsicCollapsedHeights() {
        let expandedHeight = hostedPadConfigurationHeight(initiallyExpanded: true)
        let collapsedHeight = hostedPadConfigurationHeight(initiallyExpanded: false)

        XCTAssertEqual(expandedHeight, PaddrStyle.padConfigurationCardHeight, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            collapsedHeight,
            PaddrStyle.cardHeaderHeight + (2 * PaddrStyle.cardPadding)
        )
        XCTAssertLessThan(collapsedHeight, expandedHeight)
    }

    func testProfilePickerPresentsPendingCreatedProfile() async throws {
        try await assertPendingProfilePicker(
            expectedName: "Third",
            operation: { $0.createProfile(named: "Third") }
        )
    }

    func testProfilePickerPresentsPendingDuplicatedProfile() async throws {
        try await assertPendingProfilePicker(
            expectedName: "Default Copy",
            operation: { $0.duplicateActiveProfile() }
        )
    }

    func testFiveStatusPillsFitMinimumWindowWidthWithUnavailableBattery() async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)
        XCTAssertNil(model.receiverDescription)
        XCTAssertFalse(model.controllerConnected)
        XCTAssertNil(model.batteryStatus)

        assertApplyBarFitsMinimumWindow(model: model)
    }

    func testFiveStatusPillsFitMinimumWindowWidthWithLongestBatteryValue() async throws {
        let store = BlockingProfileStore()
        let session = PresentationSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                store: store,
                session: session,
                receiver: "Fake receiver"
            )
        )
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)
        let didStart = await waitUntil { await session.startCount == 1 }
        XCTAssertTrue(didStart)
        await session.send(.controllerConnected)
        await session.send(.batteryUpdated(.init(chargeState: .chargingDone, percentage: 100)))
        let didPublishBattery = await waitUntil { model.batteryStatus?.percentage == 100 }
        XCTAssertTrue(didPublishBattery)

        assertApplyBarFitsMinimumWindow(model: model)
        _ = await session.stop()
    }

    private func assertApplyBarFitsMinimumWindow(
        model: PaddrMenuModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let controller = NSHostingController(rootView: ApplyBarView(model: model))
        let fitted = controller.sizeThatFits(
            in: NSSize(width: PaddrStyle.minimumWindowSize.width, height: 400)
        )
        XCTAssertLessThanOrEqual(
            fitted.width,
            PaddrStyle.minimumWindowSize.width + 0.5,
            file: file,
            line: line
        )
        XCTAssertGreaterThan(fitted.height, 0, file: file, line: line)
    }

    private func hostedPadConfigurationHeight(initiallyExpanded: Bool) -> CGFloat {
        let view = PadConfigurationView(
            side: .left,
            configuration: .constant(TrackIsBackConfiguration.default.left),
            initiallyExpanded: initiallyExpanded
        )
        .frame(width: 700)
        let hostingView = NSHostingView(rootView: view)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    private func assertPendingProfilePicker(
        expectedName: String,
        operation: @MainActor (PaddrMenuModel) -> Bool
    ) async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }

        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)
        XCTAssertTrue(operation(model))
        let didStartSave = await waitUntil { store.didStartSave }
        XCTAssertTrue(didStartSave)

        guard case let .switching(to: pendingID, named: pendingName) = model.profileSelectionPresentation else {
            return XCTFail("Expected a pending profile selection")
        }
        XCTAssertEqual(pendingName, expectedName)
        XCTAssertFalse(model.profiles.contains(where: { $0.id == pendingID }))

        let presentation = ProfileControlsView(model: model).profilePickerPresentation
        let pendingOption = try XCTUnwrap(presentation.options.first { $0.id == pendingID })
        XCTAssertEqual(pendingOption.label, "Switching to \(expectedName)…")
        XCTAssertEqual(presentation.accessibilityValue, "Switching to \(expectedName)")
    }

    private func firstDescendant<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> ViewType? {
        if let match = view as? ViewType { return match }
        return view.subviews.lazy.compactMap { self.firstDescendant(of: type, in: $0) }.first
    }

    private func dependencies(
        store: BlockingProfileStore,
        session: any TrackpadSessionControlling = InertSession(),
        receiver: String? = nil
    ) -> MenuDependencies {
        MenuDependencies(
            session: session,
            loadProfiles: { ConfigurationProfileLoadResult(document: .default) },
            saveProfiles: store.save,
            probeReceiver: { receiver },
            accessibilityTrusted: { _ in true },
            openPrivacySettings: { _ in },
            sleep: { duration in try await Task.sleep(for: duration) },
            reconnectDelay: { _ in throw CancellationError() }
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private struct InertSession: TrackpadSessionControlling {
    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @discardableResult
    func stop() async -> TrackpadSessionStopOutcome { .clean }
}

private actor PresentationSession: TrackpadSessionControlling {
    private var continuation: AsyncStream<TrackpadSessionEvent>.Continuation?
    private(set) var startCount = 0

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        startCount += 1
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        self.continuation = continuation
        return stream
    }

    @discardableResult
    func stop() async -> TrackpadSessionStopOutcome {
        continuation?.finish()
        continuation = nil
        return .clean
    }

    func send(_ event: TrackpadSessionEvent) {
        continuation?.yield(event)
    }
}

private final class BlockingProfileStore: @unchecked Sendable {
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var saveStarted = false
    private var saveReleased = false

    var didStartSave: Bool {
        lock.withLock { saveStarted }
    }

    func save(_ document: ConfigurationProfileDocument) {
        lock.withLock { saveStarted = true }
        gate.wait()
    }

    func releaseSave() {
        let shouldSignal = lock.withLock {
            guard !saveReleased else { return false }
            saveReleased = true
            return true
        }
        if shouldSignal {
            gate.signal()
        }
    }
}
