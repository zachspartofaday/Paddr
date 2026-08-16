import AppKit
import Dispatch
import SwiftUI
import XCTest

import PaddrAppSupport
@testable import PaddrMenu
import PaddrCore

@MainActor
final class MenuViewPresentationTests: XCTestCase {
    func testCapacitivePadSurfaceKeepsFiniteBoundsAcrossAdaptiveEnvironments() {
        let size = NSSize(width: PaddrStyle.zoneMapWidth, height: PaddrStyle.zoneMapHeight)

        for colorScheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                for reduceTransparency in [false, true] {
                    let view = CapacitivePadSurface()
                        .environment(\.colorScheme, colorScheme)
                        .environment(\._colorSchemeContrast, contrast)
                        .environment(\._accessibilityReduceTransparency, reduceTransparency)
                        .frame(width: size.width, height: size.height)
                    let hostingView = NSHostingView(rootView: view)
                    hostingView.frame = NSRect(origin: .zero, size: size)
                    hostingView.layoutSubtreeIfNeeded()

                    XCTAssertTrue(hostingView.fittingSize.width.isFinite)
                    XCTAssertTrue(hostingView.fittingSize.height.isFinite)
                    XCTAssertEqual(hostingView.fittingSize.width, size.width, accuracy: 0.5)
                    XCTAssertEqual(hostingView.fittingSize.height, size.height, accuracy: 0.5)
                    XCTAssertTrue(hostingView.accessibilityChildren()?.isEmpty ?? true)
                }
            }
        }
    }

    func testEveryOnboardingPageFitsMinimumGuideWindow() throws {
        let model = PaddrMenuModel(dependencies: dependencies(store: BlockingProfileStore()))

        for pageIndex in 0..<OnboardingPager.pageCount {
            var pager = OnboardingPager()
            for _ in 0..<pageIndex { pager.advance() }
            let view = OnboardingGuideView(
                model: model,
                onSkip: {},
                onComplete: {},
                initialPager: pager
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.minimumGuideWindowSize)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertEqual(
                hostingView.fittingSize.height,
                PaddrStyle.minimumGuideWindowSize.height,
                accuracy: 0.5
            )
            let scrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hostingView))
            let documentView = try XCTUnwrap(scrollView.documentView)
            documentView.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(
                documentView.fittingSize.height,
                scrollView.contentSize.height + 0.5,
                "Guide page \(pageIndex + 1) should not require scrolling"
            )
        }
    }

    func testEveryPadModeAndZoneLayoutFitsExpandedCardAtMinimumWidth() {
        var configurations = PadMode.allCases.map { PadConfiguration(mode: $0) }
        configurations += PadZoneLayout.allCases.map { layout in
            var configuration = PadConfiguration(mode: .dpad)
            configuration.zoneLayout = layout
            return configuration
        }
        let size = NSSize(
            width: PaddrStyle.minimumWindowSize.width - (2 * PaddrStyle.panelPadding),
            height: PaddrStyle.padConfigurationCardHeight
        )

        for configuration in configurations {
            let view = PadConfigurationView(
                side: .left,
                configuration: .constant(configuration),
                initiallyExpanded: true
            )
            .frame(width: size.width, height: size.height)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: size)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertTrue(hostingView.fittingSize.width.isFinite)
            XCTAssertEqual(hostingView.fittingSize.height, size.height, accuracy: 0.5)
            for control in descendants(of: NSControl.self, in: hostingView) {
                assertControlFits(control, in: hostingView)
            }
        }
    }

    func testPointerToggleFitsDefaultPadColumnWidth() throws {
        let size = NSSize(
            width: PaddrStyle.padColumnWidth,
            height: PaddrStyle.padConfigurationCardHeight
        )
        let view = PadConfigurationView(
            side: .right,
            configuration: .constant(PadConfiguration(mode: .mouse)),
            initiallyExpanded: true
        )
        .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        let toggle = try XCTUnwrap(firstDescendant(of: NSSwitch.self, in: hostingView))
        XCTAssertEqual(toggle.state, .on)
        assertControlFits(toggle, in: hostingView)
    }

    func testPointerSettingExtremesFitAndPreserveSwitchSemantics() throws {
        let cases: [(Double, Double, Double, CenterTapTrackingMode, NSControl.StateValue)] = [
            (
                ConfigurationLimits.sensitivity.lowerBound,
                ConfigurationLimits.mouseAcceleration.lowerBound,
                ConfigurationLimits.mouseDeadzone.lowerBound,
                .coupled,
                .off
            ),
            (
                ConfigurationLimits.sensitivity.upperBound,
                ConfigurationLimits.mouseAcceleration.upperBound,
                ConfigurationLimits.mouseDeadzone.upperBound,
                .decoupled,
                .on
            )
        ]
        let size = NSSize(
            width: PaddrStyle.minimumWindowSize.width - (2 * PaddrStyle.panelPadding),
            height: PaddrStyle.padConfigurationCardHeight
        )

        for (sensitivity, acceleration, radius, trackingMode, switchState) in cases {
            var configuration = PadConfiguration(mode: .mouse)
            configuration.sensitivity = sensitivity
            configuration.mouseAcceleration = acceleration
            configuration.mouseDeadzone = radius
            configuration.centerTapTrackingMode = trackingMode
            let view = PadConfigurationView(
                side: .right,
                configuration: .constant(configuration),
                initiallyExpanded: true
            )
            .frame(width: size.width, height: size.height)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: size)
            hostingView.layoutSubtreeIfNeeded()

            let toggle = try XCTUnwrap(firstDescendant(of: NSSwitch.self, in: hostingView))
            XCTAssertEqual(toggle.state, switchState)
            for control in descendants(of: NSControl.self, in: hostingView) {
                assertControlFits(control, in: hostingView)
            }
        }
    }

    func testOnboardingPermissionStatesFitMinimumGuideWindow() throws {
        let states: [(Bool, InputMonitoringAccess)] = [
            (true, .granted),
            (false, .denied)
        ]

        for (accessibilityGranted, inputMonitoringAccess) in states {
            var pager = OnboardingPager()
            pager.advance()
            pager.advance()
            let model = PaddrMenuModel(
                dependencies: dependencies(
                    store: BlockingProfileStore(),
                    accessibilityGranted: accessibilityGranted,
                    inputMonitoringAccess: inputMonitoringAccess
                )
            )
            let view = OnboardingGuideView(
                model: model,
                onSkip: {},
                onComplete: {},
                initialPager: pager
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.minimumGuideWindowSize)
            hostingView.layoutSubtreeIfNeeded()

            XCTAssertEqual(
                hostingView.fittingSize.height,
                PaddrStyle.minimumGuideWindowSize.height,
                accuracy: 0.5
            )
            let scrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hostingView))
            let documentView = try XCTUnwrap(scrollView.documentView)
            documentView.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(
                documentView.fittingSize.height,
                scrollView.contentSize.height + 0.5
            )
            for control in descendants(of: NSControl.self, in: hostingView) {
                assertControlFits(control, in: hostingView)
            }
        }
    }

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

    func testPointerTrackingToggleReflectsDefaultsAndLegacyBindingAtRadiusZero() throws {
        let defaultView = PadConfigurationView(
            side: .right,
            configuration: .constant(PadConfiguration(mode: .mouse)),
            initiallyExpanded: true
        )
        .frame(width: PaddrStyle.minimumWindowSize.width - (2 * PaddrStyle.panelPadding))
        let defaultHostingView = NSHostingView(rootView: defaultView)
        defaultHostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.minimumWindowSize.width - (2 * PaddrStyle.panelPadding),
                height: PaddrStyle.padConfigurationCardHeight
            )
        )
        defaultHostingView.layoutSubtreeIfNeeded()

        let defaultToggle = try XCTUnwrap(
            firstDescendant(of: NSSwitch.self, in: defaultHostingView)
        )
        XCTAssertEqual(defaultToggle.state, .on)
        XCTAssertEqual(defaultToggle.accessibilityRoleDescription(), "switch")
        XCTAssertEqual(accessibilityIntegerValue(of: defaultToggle), 1)
        XCTAssertTrue(defaultToggle.isEnabled)
        let defaultControls = descendants(of: NSControl.self, in: defaultHostingView)
        XCTAssertGreaterThanOrEqual(defaultControls.count, 2)
        for control in defaultControls {
            assertControlFits(control, in: defaultHostingView)
        }

        var legacy = try JSONDecoder().decode(
            PadConfiguration.self,
            from: Data("{\"mode\":\"mouse\",\"mouseDeadzone\":0}".utf8)
        )
        let legacyBinding = Binding(
            get: { legacy },
            set: { legacy = $0 }
        )
        let legacyView = PadConfigurationView(
            side: .right,
            configuration: legacyBinding,
            initiallyExpanded: true
        )
        .frame(width: PaddrStyle.padColumnWidth)
        let legacyHostingView = NSHostingView(rootView: legacyView)
        legacyHostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.padColumnWidth,
                height: PaddrStyle.padConfigurationCardHeight
            )
        )
        legacyHostingView.layoutSubtreeIfNeeded()

        let legacyToggle = try XCTUnwrap(
            firstDescendant(of: NSSwitch.self, in: legacyHostingView)
        )
        XCTAssertEqual(legacy.centerTapTrackingMode, .coupled)
        XCTAssertEqual(legacyToggle.state, .off)
        XCTAssertEqual(legacyToggle.accessibilityRoleDescription(), "switch")
        XCTAssertEqual(accessibilityIntegerValue(of: legacyToggle), 0)
        XCTAssertTrue(legacyToggle.isEnabled)
        legacyToggle.performClick(nil)
        legacyHostingView.layoutSubtreeIfNeeded()
        XCTAssertEqual(legacy.centerTapTrackingMode, .decoupled)
        XCTAssertEqual(legacyToggle.state, .on)
        XCTAssertEqual(accessibilityIntegerValue(of: legacyToggle), 1)
        assertControlFits(legacyToggle, in: legacyHostingView)
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
            configuration: .constant(PaddrConfiguration.default.left),
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

    private func accessibilityIntegerValue(of object: NSObject) -> Int? {
        let selector = NSSelectorFromString("accessibilityValue")
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() as? NSNumber else {
            return nil
        }
        return value.intValue
    }

    private func assertControlFits(
        _ control: NSControl,
        in hostingView: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = control.convert(control.bounds, to: hostingView)
        XCTAssertGreaterThanOrEqual(frame.minX, hostingView.bounds.minX - 0.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, hostingView.bounds.minY - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, hostingView.bounds.maxX + 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, hostingView.bounds.maxY + 0.5, file: file, line: line)
    }

    private func descendants<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> [ViewType] {
        let current = (view as? ViewType).map { [$0] } ?? []
        return current + view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func firstDescendant<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> ViewType? {
        descendants(of: type, in: view).first
    }

    private func dependencies(
        store: BlockingProfileStore,
        session: any TrackpadSessionControlling = InertSession(),
        receiver: String? = nil,
        accessibilityGranted: Bool = true,
        inputMonitoringAccess: InputMonitoringAccess = .granted
    ) -> MenuDependencies {
        MenuDependencies(
            session: session,
            loadProfiles: { ConfigurationProfileLoadResult(document: .default) },
            saveProfiles: store.save,
            probeReceiver: { receiver },
            accessibilityTrusted: { _ in accessibilityGranted },
            inputMonitoringAccess: { _ in inputMonitoringAccess },
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
        configuration: PaddrConfiguration,
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
        configuration: PaddrConfiguration,
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
