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

        hostingView.frame.size.width = PaddrStyle.Metrics.defaultContentWidth
        await settle(hostingView)

        let inlineSize = hostingView.fittingSize
        XCTAssertLessThanOrEqual(inlineSize.width, PaddrStyle.Metrics.defaultContentWidth + 0.5)
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
        model.configuration.left.mode = .dpad

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

    func testNativePadModeControlIdentifiersRemainDistinctInHostedConfiguration() async {
        let model = makeMenuModel()
        let didInitialize = await waitUntil { model.isInitialized && model.hasSystemAccess }
        XCTAssertTrue(didInitialize)

        let hostingView = NSHostingView(rootView: ConfigurationView(model: model))
        hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.Metrics.defaultWindowSize)
        await settle(hostingView)

        let identifiers = modeSelectors(in: hostingView).compactMap { $0.identifier?.rawValue }
        XCTAssertEqual(
            Set(identifiers),
            ["paddr.pad-mode.left", "paddr.pad-mode.right"],
            "The two simultaneously hosted native mode controls need distinct stable IDs"
        )
        XCTAssertEqual(identifiers.count, 2)
    }

    func testRestoredWideConfigurationUsesAvailableWidthWithoutDeadGutters() async throws {
        let model = makeMenuModel()
        let didInitialize = await waitUntil { model.isInitialized && model.hasSystemAccess }
        XCTAssertTrue(didInitialize)
        let restoredWidth: CGFloat = 1_120
        let hostingView = NSHostingView(rootView: ConfigurationView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: restoredWidth, height: 900)
        await settle(hostingView)

        let left = try XCTUnwrap(modeSelector(side: .left, in: hostingView))
        let right = try XCTUnwrap(modeSelector(side: .right, in: hostingView))
        let availableContentWidth = restoredWidth - (2 * PaddrStyle.Metrics.outerSpacing)
        let expectedColumnWidth = (
            availableContentWidth - PaddrStyle.Spacing.s3
        ) / 2

        XCTAssertEqual(
            abs(frame(of: left, in: hostingView).midX - frame(of: right, in: hostingView).midX),
            expectedColumnWidth + PaddrStyle.Spacing.s3,
            accuracy: 1,
            "A restored wide window must expand both pad columns instead of centering an 820pt island"
        )
    }

    func testDualPadEditorsMountSideBySideAtTheDefaultContentWidth() async throws {
        let state = DualPadEvidenceState(configuration: .default)
        let hostingView = dualPadHostingView(state: state)
        await settle(hostingView)

        XCTAssertEqual(modeSelectors(in: hostingView).count, 2)
        let left = try XCTUnwrap(modeSelector(side: .left, in: hostingView))
        let right = try XCTUnwrap(modeSelector(side: .right, in: hostingView))
        XCTAssertEqual(
            frame(of: left, in: hostingView).midY,
            frame(of: right, in: hostingView).midY,
            accuracy: 1
        )
        XCTAssertGreaterThan(
            abs(frame(of: left, in: hostingView).midX - frame(of: right, in: hostingView).midX),
            PaddrStyle.Metrics.row
        )
        XCTAssertEqual(
            abs(frame(of: left, in: hostingView).midX - frame(of: right, in: hostingView).midX),
            PaddrStyle.padColumnWidth + PaddrStyle.Spacing.s3,
            accuracy: 1,
            "The two rendered editors should occupy equal columns at the default width"
        )
        XCTAssertEqual(
            PaddrStyle.padColumnWidth,
            (PaddrStyle.Metrics.defaultContentWidth - PaddrStyle.Spacing.s3) / 2
        )

        let leftCard = try XCTUnwrap(
            renderedCardRuns(atX: 20, in: hostingView).first
        )
        let rightCard = try XCTUnwrap(
            renderedCardRuns(
                atX: PaddrStyle.padColumnWidth + PaddrStyle.Spacing.s3 + 20,
                in: hostingView
            ).first
        )
        XCTAssertEqual(
            leftCard.upperBound - leftCard.lowerBound,
            rightCard.upperBound - rightCard.lowerBound,
            accuracy: 1,
            "The rendered Scroll and Pointer card backgrounds must end on the same row"
        )
        XCTAssertLessThan(
            leftCard.upperBound - leftCard.lowerBound,
            hostingView.bounds.height / 2,
            "Equal-height cards must use their tallest intrinsic height, not the arbitrary host height"
        )
    }

    func testDualPadBreakpointContainsControlsImmediatelyBelowAtAndAboveIt() async throws {
        let state = DualPadEvidenceState(configuration: .default)
        let hostingView = dualPadHostingView(state: state)

        for width in [
            PaddrStyle.Metrics.padEditorColumnsBreakpoint - 1,
            PaddrStyle.Metrics.padEditorColumnsBreakpoint,
            PaddrStyle.Metrics.padEditorColumnsBreakpoint + 1
        ] {
            hostingView.frame.size.width = width
            await settle(hostingView)

            let left = try XCTUnwrap(modeSelector(side: .left, in: hostingView))
            let right = try XCTUnwrap(modeSelector(side: .right, in: hostingView))
            if width < PaddrStyle.Metrics.padEditorColumnsBreakpoint {
                XCTAssertGreaterThan(
                    abs(frame(of: left, in: hostingView).midY
                        - frame(of: right, in: hostingView).midY),
                    PaddrStyle.Metrics.row
                )
            } else {
                XCTAssertEqual(
                    frame(of: left, in: hostingView).midY,
                    frame(of: right, in: hostingView).midY,
                    accuracy: 1
                )
            }

            for control in descendants(of: NSControl.self, in: hostingView) {
                let controlFrame = frame(of: control, in: hostingView)
                XCTAssertGreaterThanOrEqual(
                    controlFrame.minX,
                    hostingView.bounds.minX - 0.5,
                    "\(type(of: control)) escapes the leading edge at \(width)pt"
                )
                XCTAssertLessThanOrEqual(
                    controlFrame.maxX,
                    hostingView.bounds.maxX + 0.5,
                    "\(type(of: control)) escapes the trailing edge at \(width)pt"
                )
            }
        }
    }

    func testDualPadEditorsMutateLeftAndRightIndependently() async throws {
        var initialConfiguration = PaddrConfiguration.default
        initialConfiguration.left.mode = .scroll
        initialConfiguration.right.mode = .mouse
        let state = DualPadEvidenceState(configuration: initialConfiguration)
        let hostingView = dualPadHostingView(state: state)
        await settle(hostingView)

        let originalRight = state.configuration.right
        let leftModeSelector = try XCTUnwrap(modeSelector(side: .left, in: hostingView))
        leftModeSelector.selectedSegment = 3
        _ = leftModeSelector.sendAction(leftModeSelector.action, to: leftModeSelector.target)
        await settle(hostingView)

        XCTAssertEqual(state.configuration.left.mode, .dpad)
        XCTAssertEqual(state.configuration.right, originalRight)

        let originalLeft = state.configuration.left
        let rightModeSelector = try XCTUnwrap(modeSelector(side: .right, in: hostingView))
        rightModeSelector.selectedSegment = 0
        _ = rightModeSelector.sendAction(rightModeSelector.action, to: rightModeSelector.target)
        await settle(hostingView)

        XCTAssertEqual(state.configuration.left, originalLeft)
        XCTAssertEqual(state.configuration.right.mode, .disabled)
        XCTAssertEqual(modeSelectors(in: hostingView).count, 2)
    }

    func testDualPadEditorsStackAtNarrowWidthWithoutRemountingEitherEditor() async throws {
        let state = DualPadEvidenceState(configuration: .default)
        let hostingView = dualPadHostingView(state: state)
        await settle(hostingView)

        let initialLeft = try XCTUnwrap(modeSelector(side: .left, in: hostingView))
        let initialRight = try XCTUnwrap(modeSelector(side: .right, in: hostingView))
        XCTAssertEqual(
            frame(of: initialLeft, in: hostingView).midY,
            frame(of: initialRight, in: hostingView).midY,
            accuracy: 1
        )

        hostingView.frame.size.width = PaddrStyle.Metrics.padEditorColumnsBreakpoint - 1
        await settle(hostingView)

        let reflowedLeft = try XCTUnwrap(modeSelector(side: .left, in: hostingView))
        let reflowedRight = try XCTUnwrap(modeSelector(side: .right, in: hostingView))
        XCTAssertGreaterThan(
            abs(frame(of: reflowedLeft, in: hostingView).midY
                - frame(of: reflowedRight, in: hostingView).midY),
            PaddrStyle.Metrics.row
        )
        XCTAssertTrue(initialLeft === reflowedLeft)
        XCTAssertTrue(initialRight === reflowedRight)
        XCTAssertEqual(modeSelectors(in: hostingView).count, 2)

        let stackedCards = renderedCardRuns(atX: 20, in: hostingView)
        XCTAssertEqual(stackedCards.count, 2)
        let leftEditor = try XCTUnwrap(stackedCards.first)
        let rightEditor = try XCTUnwrap(stackedCards.last)
        XCTAssertLessThan(
            leftEditor.upperBound - leftEditor.lowerBound,
            hostingView.bounds.height / 2
        )
        XCTAssertLessThan(
            rightEditor.upperBound - rightEditor.lowerBound,
            hostingView.bounds.height / 2
        )
    }

    func testEqualHeightColumnsReturnToNaturalIndependentStackedHeights() async throws {
        let recorder = AdaptiveSplitSentinelRecorder()
        let hostingView = NSHostingView(
            rootView: EqualHeightSplitEvidenceHarness(recorder: recorder)
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: PaddrStyle.Metrics.defaultContentWidth,
            height: 1_400
        )
        await settle(hostingView)

        let initialShort = try XCTUnwrap(boundsProbe("short", in: hostingView))
        let initialTall = try XCTUnwrap(boundsProbe("tall", in: hostingView))
        XCTAssertEqual(
            frame(of: initialShort, in: hostingView).height,
            frame(of: initialTall, in: hostingView).height,
            accuracy: 0.5
        )
        XCTAssertEqual(frame(of: initialTall, in: hostingView).height, 420, accuracy: 0.5)
        XCTAssertLessThan(
            frame(of: initialTall, in: hostingView).height,
            hostingView.bounds.height / 2,
            "The equal-height layout must ignore the arbitrary host-height proposal"
        )

        hostingView.frame.size.width = PaddrStyle.Metrics.padEditorColumnsBreakpoint - 1
        await settle(hostingView)

        let stackedShort = try XCTUnwrap(boundsProbe("short", in: hostingView))
        let stackedTall = try XCTUnwrap(boundsProbe("tall", in: hostingView))
        XCTAssertTrue(initialShort === stackedShort)
        XCTAssertTrue(initialTall === stackedTall)
        XCTAssertEqual(frame(of: stackedShort, in: hostingView).height, 260, accuracy: 0.5)
        XCTAssertEqual(frame(of: stackedTall, in: hostingView).height, 420, accuracy: 0.5)
        XCTAssertGreaterThan(
            abs(
                frame(of: stackedShort, in: hostingView).midY
                    - frame(of: stackedTall, in: hostingView).midY
            ),
            PaddrStyle.Metrics.row
        )
        XCTAssertEqual(recorder.mountCount(for: "short"), 1)
        XCTAssertEqual(recorder.mountCount(for: "tall"), 1)
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

    private func dualPadHostingView(state: DualPadEvidenceState) -> NSHostingView<DualPadEvidenceHarness> {
        let hostingView = NSHostingView(rootView: DualPadEvidenceHarness(state: state))
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: PaddrStyle.Metrics.defaultContentWidth,
            height: 1_400
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

    private func modeSelectors(in view: NSView) -> [NSSegmentedControl] {
        descendants(of: NSSegmentedControl.self, in: view).filter { $0.segmentCount == 4 }
    }

    private func modeSelector(side: PadSide, in view: NSView) -> NSSegmentedControl? {
        modeSelectors(in: view).first {
            $0.identifier?.rawValue == PaddrAccessibility.identifier("pad-mode", side.rawValue)
        }
    }

    private func sentinelButton(_ identifier: String, in view: NSView) -> NSButton? {
        descendants(of: NSButton.self, in: view).first {
            $0.identifier?.rawValue == identifier
        }
    }

    private func boundsProbe(_ identifier: String, in view: NSView) -> AdaptiveSplitBoundsNSView? {
        descendants(of: AdaptiveSplitBoundsNSView.self, in: view).first {
            $0.identifier?.rawValue == identifier
        }
    }

    private func frame(of view: NSView, in ancestor: NSView) -> NSRect {
        view.convert(view.bounds, to: ancestor)
    }

    private func renderedCardRuns(
        atX pointX: CGFloat,
        in hostingView: NSView
    ) -> [ClosedRange<CGFloat>] {
        guard let representation = hostingView.bitmapImageRepForCachingDisplay(
            in: hostingView.bounds
        ) else {
            return []
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        let xScale = CGFloat(representation.pixelsWide) / hostingView.bounds.width
        let yScale = CGFloat(representation.pixelsHigh) / hostingView.bounds.height
        let pixelX = min(
            representation.pixelsWide - 1,
            max(0, Int((pointX * xScale).rounded(.down)))
        )
        var runs: [ClosedRange<CGFloat>] = []
        var start: Int?

        for pixelY in 0..<representation.pixelsHigh {
            let isCardPixel = (representation.colorAt(x: pixelX, y: pixelY)?.alphaComponent ?? 0) > 0.02
            if isCardPixel, start == nil {
                start = pixelY
            } else if !isCardPixel, let runStart = start {
                runs.append(
                    (CGFloat(runStart) / yScale)...(CGFloat(pixelY - 1) / yScale)
                )
                start = nil
            }
        }
        if let runStart = start {
            runs.append(
                (CGFloat(runStart) / yScale)...(CGFloat(representation.pixelsHigh - 1) / yScale)
            )
        }
        return runs.filter {
            $0.upperBound - $0.lowerBound > PaddrStyle.Metrics.row
        }
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
private final class DualPadEvidenceState {
    var configuration: PaddrConfiguration

    init(configuration: PaddrConfiguration) {
        self.configuration = configuration
    }
}

private struct DualPadEvidenceHarness: View {
    @Bindable var state: DualPadEvidenceState

    var body: some View {
        DualPadConfigurationView(
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

private struct EqualHeightSplitEvidenceHarness: View {
    let recorder: AdaptiveSplitSentinelRecorder

    var body: some View {
        PaddrAdaptiveSplitView(
            equalHeightColumnsBreakpoint: PaddrStyle.Metrics.padEditorColumnsBreakpoint,
            leading: {
                EqualHeightEvidenceCard(
                    identifier: "short",
                    naturalHeight: 260,
                    recorder: recorder
                )
            },
            trailing: {
                EqualHeightEvidenceCard(
                    identifier: "tall",
                    naturalHeight: 420,
                    recorder: recorder
                )
            }
        )
    }
}

private struct EqualHeightEvidenceCard: View {
    @Environment(\.paddrFillsEqualHeightColumn) private var fillsEqualHeightColumn

    let identifier: String
    let naturalHeight: CGFloat
    let recorder: AdaptiveSplitSentinelRecorder

    var body: some View {
        Color.clear
            .frame(height: naturalHeight)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsEqualHeightColumn ? .infinity : nil,
                alignment: .topLeading
            )
            .paddrCard()
            .background {
                AdaptiveSplitBoundsProbe(identifier: identifier, recorder: recorder)
            }
    }
}

private final class AdaptiveSplitBoundsNSView: NSView {}

private struct AdaptiveSplitBoundsProbe: NSViewRepresentable {
    let identifier: String
    let recorder: AdaptiveSplitSentinelRecorder

    func makeNSView(context: Context) -> AdaptiveSplitBoundsNSView {
        let view = AdaptiveSplitBoundsNSView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        recorder.recordMount(identifier: identifier)
        return view
    }

    func updateNSView(_ view: AdaptiveSplitBoundsNSView, context: Context) {}
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
