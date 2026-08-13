import AppKit
import Dispatch
import SwiftUI
import XCTest

import PaddrAppSupport
@testable import TrackIsBackMenu
import TrackIsBackCore

@MainActor
final class MenuViewPresentationTests: XCTestCase {
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

    private func dependencies(store: BlockingProfileStore) -> MenuDependencies {
        MenuDependencies(
            session: InertSession(),
            loadProfiles: { ConfigurationProfileLoadResult(document: .default) },
            saveProfiles: store.save,
            probeReceiver: { nil },
            accessibilityTrusted: { _ in true },
            openPrivacySettings: { _ in },
            sleep: { duration in try await Task.sleep(for: duration) }
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() {
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
        observeOnly: Bool
    ) async -> AsyncStream<TrackpadSessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
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
