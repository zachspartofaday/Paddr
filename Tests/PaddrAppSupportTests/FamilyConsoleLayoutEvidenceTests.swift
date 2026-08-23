import AppKit
import Observation
import SwiftUI
import XCTest

import PaddrAppSupport
import PaddrCore
@testable import PaddrMenu

@MainActor
final class FamilyConsoleLayoutEvidenceTests: XCTestCase {
    func testTopControlsReflowAt680PointsAndFitAvailableWidth() async {
        let model = makeMenuModel()
        let didInitialize = await waitUntil { model.isInitialized && model.hasSystemAccess }
        XCTAssertTrue(didInitialize)

        let hostingView = NSHostingView(rootView: TopControlsView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 240)
        await settle(hostingView)

        let compactSize = hostingView.fittingSize
        XCTAssertLessThanOrEqual(compactSize.width, 680.5)
        XCTAssertGreaterThan(compactSize.height, 0)

        hostingView.frame.size.width = PaddrStyle.Metrics.contentMaxWidth
        await settle(hostingView)

        let inlineSize = hostingView.fittingSize
        XCTAssertLessThanOrEqual(inlineSize.width, PaddrStyle.Metrics.contentMaxWidth + 0.5)
        XCTAssertGreaterThan(
            compactSize.height,
            inlineSize.height + (PaddrStyle.Metrics.row / 2),
            "The controls should use two rows at 680 points and one row above the breakpoint"
        )
    }

    func testApplyBarPreservesFullNextActionInsideMinimumWidth() async {
        let model = makeMenuModel(receiver: "Test puck")
        let didInitialize = await waitUntil { model.isInitialized && model.hasSystemAccess }
        XCTAssertTrue(didInitialize)
        XCTAssertEqual(model.readiness.nextAction, .connectController)
        XCTAssertEqual(
            String(localized: model.readiness.nextAction.title),
            "Connect the controller through the puck"
        )

        let hostingView = NSHostingView(rootView: ApplyBarView(model: model))
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: PaddrStyle.Metrics.minimumWindowSize.width,
            height: 180
        )
        await settle(hostingView)
        hostingView.frame.size.height = hostingView.fittingSize.height
        await settle(hostingView)

        XCTAssertGreaterThan(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.commandBar,
            "The minimum-width bar should move guidance below the status cells"
        )
        XCTAssertLessThanOrEqual(
            hostingView.fittingSize.width,
            PaddrStyle.Metrics.minimumWindowSize.width + 0.5
        )

        hostingView.frame.size.width = 800
        await settle(hostingView)
        XCTAssertGreaterThan(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.commandBar,
            "Sub-default widths must keep the nonoverflowing stacked payload"
        )

        hostingView.frame.size.width = PaddrStyle.Metrics.defaultWindowSize.width
        await settle(hostingView)
        XCTAssertEqual(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.commandBar,
            accuracy: 0.5,
            "The default window width should restore the single-row status bar"
        )
    }

    func testConfigurationControlsStayHorizontallyContainedAtMinimumWindowWidth() async {
        let model = makeMenuModel()
        let didInitialize = await waitUntil { model.isInitialized && model.hasSystemAccess }
        XCTAssertTrue(didInitialize)

        let hostingView = NSHostingView(rootView: ConfigurationView(model: model))
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: PaddrStyle.Metrics.minimumWindowSize.width, height: 900)
        )
        await settle(hostingView)

        let controls = descendants(of: NSControl.self, in: hostingView)
        XCTAssertGreaterThanOrEqual(controls.count, 2)
        for control in controls {
            let controlFrame = frame(of: control, in: hostingView)
            XCTAssertGreaterThanOrEqual(controlFrame.minX, hostingView.bounds.minX - 0.5)
            XCTAssertLessThanOrEqual(controlFrame.maxX, hostingView.bounds.maxX + 0.5)
        }
    }

    func testFocusedPadMountsOneSideSelectorAndOneDetailTree() async {
        let state = FocusedPadEvidenceState(configuration: .default)
        let hostingView = focusedPadHostingView(state: state)
        await settle(hostingView)

        XCTAssertEqual(sideSelectors(in: hostingView).count, 1)
        XCTAssertEqual(modeSelectors(in: hostingView).count, 1)
        XCTAssertEqual(descendants(of: NSSegmentedControl.self, in: hostingView).count, 2)
    }

    func testFocusedRightSideMutatesIndependentlyAndSurvivesBoundProfileReplacement() async throws {
        var initialConfiguration = PaddrConfiguration.default
        initialConfiguration.left.mode = .scroll
        initialConfiguration.right.mode = .mouse
        let state = FocusedPadEvidenceState(configuration: initialConfiguration)
        let hostingView = focusedPadHostingView(state: state)
        await settle(hostingView)

        let selector = try XCTUnwrap(sideSelectors(in: hostingView).first)
        selector.selectedSegment = 1
        _ = selector.sendAction(selector.action, to: selector.target)
        await settle(hostingView)

        XCTAssertEqual(sideSelectors(in: hostingView).first?.selectedSegment, 1)
        XCTAssertEqual(modeSelectors(in: hostingView).first?.selectedSegment, 1)

        let originalLeft = state.configuration.left
        let rightModeSelector = try XCTUnwrap(modeSelectors(in: hostingView).first)
        rightModeSelector.selectedSegment = 3
        _ = rightModeSelector.sendAction(rightModeSelector.action, to: rightModeSelector.target)
        await settle(hostingView)

        XCTAssertEqual(state.configuration.left, originalLeft)
        XCTAssertEqual(state.configuration.right.mode, .dpad)

        var replacement = PaddrConfiguration.default
        replacement.left.mode = .disabled
        replacement.right.mode = .scroll
        state.configuration = replacement
        await settle(hostingView)

        XCTAssertEqual(
            sideSelectors(in: hostingView).first?.selectedSegment,
            1,
            "Replacing the bound profile must not reset the window-local side choice"
        )
        XCTAssertEqual(modeSelectors(in: hostingView).first?.selectedSegment, 2)
        XCTAssertEqual(sideSelectors(in: hostingView).count, 1)
        XCTAssertEqual(modeSelectors(in: hostingView).count, 1)
    }

    func testAdaptiveSplitRetainsOneStatefulIdentityPerChildAcrossReflowAndAccessibilityChange() async throws {
        let recorder = AdaptiveSplitSentinelRecorder()
        let environment = AdaptiveSplitEvidenceEnvironment()
        let hostingView = NSHostingView(
            rootView: AdaptiveSplitEvidenceHarness(
                environment: environment,
                recorder: recorder
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 820, height: 180)
        await settle(hostingView)

        let initialLeading = try XCTUnwrap(sentinelButton("leading", in: hostingView))
        let initialTrailing = try XCTUnwrap(sentinelButton("trailing", in: hostingView))
        XCTAssertEqual(
            frame(of: initialLeading, in: hostingView).width,
            PaddrStyle.Metrics.zoneMapWidth,
            accuracy: 0.5,
            "The rendered leading pad/map column must retain its protected 190-point width"
        )
        XCTAssertEqual(
            frame(of: initialLeading, in: hostingView).midY,
            frame(of: initialTrailing, in: hostingView).midY,
            accuracy: 1
        )
        initialLeading.performClick(nil)
        initialTrailing.performClick(nil)
        await settle(hostingView)
        XCTAssertEqual(recorder.value(for: "leading"), 1)
        XCTAssertEqual(recorder.value(for: "trailing"), 1)

        hostingView.frame.size.width = 640
        await settle(hostingView)
        environment.dynamicTypeSize = .accessibility1
        await settle(hostingView)

        let reflowedLeading = try XCTUnwrap(sentinelButton("leading", in: hostingView))
        let reflowedTrailing = try XCTUnwrap(sentinelButton("trailing", in: hostingView))
        XCTAssertGreaterThan(
            abs(frame(of: reflowedLeading, in: hostingView).midY
                - frame(of: reflowedTrailing, in: hostingView).midY),
            PaddrStyle.Metrics.row / 2
        )
        XCTAssertTrue(initialLeading === reflowedLeading)
        XCTAssertTrue(initialTrailing === reflowedTrailing)
        XCTAssertEqual(recorder.mountCount(for: "leading"), 1)
        XCTAssertEqual(recorder.mountCount(for: "trailing"), 1)
        XCTAssertEqual(recorder.value(for: "leading"), 1)
        XCTAssertEqual(recorder.value(for: "trailing"), 1)

        reflowedLeading.performClick(nil)
        reflowedTrailing.performClick(nil)
        await settle(hostingView)
        XCTAssertEqual(recorder.value(for: "leading"), 2)
        XCTAssertEqual(recorder.value(for: "trailing"), 2)
        XCTAssertEqual(recorder.mountCount(for: "leading"), 1)
        XCTAssertEqual(recorder.mountCount(for: "trailing"), 1)
    }

    private func focusedPadHostingView(state: FocusedPadEvidenceState) -> NSHostingView<FocusedPadEvidenceHarness> {
        let hostingView = NSHostingView(rootView: FocusedPadEvidenceHarness(state: state))
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: PaddrStyle.Metrics.contentMaxWidth,
            height: 720
        )
        return hostingView
    }

    private func makeMenuModel(receiver: String? = nil) -> PaddrMenuModel {
        PaddrMenuModel(
            dependencies: MenuDependencies(
                session: LayoutEvidenceSession(),
                loadProfiles: { ConfigurationProfileLoadResult(document: .default) },
                saveProfiles: { _ in },
                probeReceiver: { receiver },
                accessibilityTrusted: { _ in true },
                inputMonitoringAccess: { _ in .granted },
                openPrivacySettings: { _ in },
                sleep: { _ in throw CancellationError() },
                reconnectDelay: { _ in throw CancellationError() }
            )
        )
    }

    private func sideSelectors(in view: NSView) -> [NSSegmentedControl] {
        descendants(of: NSSegmentedControl.self, in: view).filter { $0.segmentCount == 2 }
    }

    private func modeSelectors(in view: NSView) -> [NSSegmentedControl] {
        descendants(of: NSSegmentedControl.self, in: view).filter { $0.segmentCount == 4 }
    }

    private func sentinelButton(_ identifier: String, in view: NSView) -> NSButton? {
        descendants(of: NSButton.self, in: view).first {
            $0.identifier?.rawValue == identifier
        }
    }

    private func frame(of view: NSView, in ancestor: NSView) -> NSRect {
        view.convert(view.bounds, to: ancestor)
    }

    private func descendants<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> [ViewType] {
        let current = (view as? ViewType).map { [$0] } ?? []
        return current + view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func settle(_ hostingView: NSView) async {
        for _ in 0..<6 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

@MainActor
@Observable
private final class FocusedPadEvidenceState {
    var configuration: PaddrConfiguration

    init(configuration: PaddrConfiguration) {
        self.configuration = configuration
    }
}

private struct FocusedPadEvidenceHarness: View {
    @Bindable var state: FocusedPadEvidenceState

    var body: some View {
        FocusedPadConfigurationView(
            configuration: $state.configuration,
            appearsEnabled: true,
            isEditable: true
        )
    }
}

private struct LayoutEvidenceSession: TrackpadSessionControlling {
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

@MainActor
@Observable
private final class AdaptiveSplitEvidenceEnvironment {
    var dynamicTypeSize: DynamicTypeSize = .medium
}

@MainActor
private final class AdaptiveSplitSentinelRecorder {
    private var mountCounts: [String: Int] = [:]
    private var values: [String: Int] = [:]

    func recordMount(identifier: String) {
        mountCounts[identifier, default: 0] += 1
    }

    func recordValue(_ value: Int, identifier: String) {
        values[identifier] = value
    }

    func mountCount(for identifier: String) -> Int {
        mountCounts[identifier, default: 0]
    }

    func value(for identifier: String) -> Int? {
        values[identifier]
    }
}

private struct AdaptiveSplitEvidenceHarness: View {
    @Bindable var environment: AdaptiveSplitEvidenceEnvironment
    let recorder: AdaptiveSplitSentinelRecorder

    var body: some View {
        PaddrAdaptiveSplitView(
            breakpoint: 680,
            leadingWidth: PaddrStyle.Metrics.zoneMapWidth,
            leading: {
                AdaptiveSplitStateSentinel(identifier: "leading", recorder: recorder)
            },
            trailing: {
                AdaptiveSplitStateSentinel(identifier: "trailing", recorder: recorder)
            }
        )
        .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
    }
}

private struct AdaptiveSplitStateSentinel: View {
    let identifier: String
    let recorder: AdaptiveSplitSentinelRecorder
    @State private var value = 0

    var body: some View {
        AdaptiveSplitSentinelButton(
            identifier: identifier,
            value: $value,
            recorder: recorder
        )
    }
}

private struct AdaptiveSplitSentinelButton: NSViewRepresentable {
    let identifier: String
    @Binding var value: Int
    let recorder: AdaptiveSplitSentinelRecorder

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Int>

        init(value: Binding<Int>) {
            self.value = value
        }

        @objc func incrementValue() {
            value.wrappedValue += 1
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSButton {
        recorder.recordMount(identifier: identifier)
        let button = NSButton(
            title: identifier,
            target: context.coordinator,
            action: #selector(Coordinator.incrementValue)
        )
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.value = $value
        button.title = "\(identifier):\(value)"
        recorder.recordValue(value, identifier: identifier)
    }
}
