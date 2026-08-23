import AppKit
import SwiftUI
import XCTest

import PaddrAppSupport
import PaddrCore
@testable import PaddrMenu

@MainActor
final class FamilyConsolePresentationTests: XCTestCase {
    func testFamilyConsoleGeometryMatchesApprovedContract() {
        XCTAssertEqual(PaddrStyle.Metrics.controlHeight, 38)
        XCTAssertEqual(PaddrStyle.Metrics.statusPill, 32)
        XCTAssertEqual(PaddrStyle.Radius.control, 7)
        XCTAssertEqual(PaddrStyle.Metrics.defaultWindowSize, NSSize(width: 1_280, height: 700))
        XCTAssertEqual(PaddrStyle.Metrics.defaultContentWidth, 1_232)
        XCTAssertEqual(PaddrStyle.Metrics.outerSpacing, 24)
        XCTAssertEqual(PaddrStyle.Inset.window, 24)
        XCTAssertEqual(PaddrStyle.Inset.card, 16)
        XCTAssertEqual(PaddrStyle.Inset.section, 16)
        XCTAssertEqual(PaddrStyle.Inset.control, 12)
        XCTAssertEqual(PaddrStyle.cardSpacing, 16)
        XCTAssertEqual(PaddrStyle.Metrics.padEditorColumnsBreakpoint, 792)
        XCTAssertEqual(PaddrStyle.minimumPadSectionWidth, 324)
        XCTAssertEqual(PaddrStyle.minimumPadColumnWidth, 388)
        XCTAssertEqual(PaddrStyle.padColumnWidth, 608)
        XCTAssertEqual(
            PaddrStyle.Metrics.padEditorColumnsBreakpoint,
            (2 * PaddrStyle.minimumPadColumnWidth) + PaddrStyle.cardSpacing
        )
        XCTAssertEqual(PaddrStyle.Metrics.statusBarInlineBreakpoint, 1_120)
    }

    func testStatusStripUsesReadinessOrder() {
        XCTAssertEqual(
            PaddrStatusKind.allCases,
            [.access, .puck, .controller, .output, .battery]
        )
    }

    func testTypographyRolesFormAStrictNativeHierarchy() {
        func height(for role: PaddrTextRole) -> CGFloat {
            let hostingView = NSHostingView(
                rootView: Text("Hierarchy").paddrTypography(role)
            )
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.height
        }

        let page = height(for: .pageTitle)
        let card = height(for: .cardTitle)
        let section = height(for: .sectionTitle)
        let band = height(for: .sectionLabel)
        let row = height(for: .rowLabel)

        XCTAssertGreaterThan(page, card)
        XCTAssertGreaterThan(card, section)
        XCTAssertGreaterThan(section, band)
        XCTAssertGreaterThan(band, row)
        XCTAssertEqual(row, height(for: .value), accuracy: 0.5)
    }

    func testFamilyConsolePaletteMatchesApprovedValues() throws {
        try assertColor(PaddrStyle.night0, red: 5, green: 6, blue: 13)
        try assertColor(PaddrStyle.night1, red: 13, green: 17, blue: 38)
        try assertColor(PaddrStyle.interfaceBlue, red: 51, green: 158, blue: 255)
        try assertColor(PaddrStyle.interfacePurple, red: 115, green: 89, blue: 255)
        try assertColor(PaddrStyle.successGreen, red: 70, green: 180, blue: 135)
        try assertColor(PaddrStyle.cautionAmber, red: 255, green: 179, blue: 64)
    }

    func testAccessibilityIdentifiersAreStableAndPaddrNamespaced() {
        XCTAssertEqual(PaddrAccessibility.slug("  Left / Right  "), "left-right")
        XCTAssertEqual(PaddrAccessibility.slug("Profile_42"), "profile-42")
        XCTAssertEqual(
            PaddrAccessibility.identifier("Pad Editor", "Left"),
            "paddr.pad-editor.left"
        )
        XCTAssertEqual(PaddrAccessibility.identifier("", "Status Item"), "paddr.status-item")
    }

    func testReadinessResolverUsesDeterministicGatePriority() {
        let cases: [(PaddrReadinessInput, PaddrReadinessNextAction)] = [
            (input(isInitialized: false), .waitForInitialization),
            (input(puckConnected: false), .refreshPuck),
            (input(inputMonitoringGranted: false), .requestInputMonitoring),
            (input(controllerConnected: false), .connectController),
            (input(accessibilityTrusted: false), .requestAccessibility),
            (input(isReleasingOutput: true), .waitForOutputRelease),
            (input(isEnabled: false), .enableOutput),
            (input(isRunning: false), .releaseTrackpads),
            (input(), .none)
        ]

        for (input, expectedAction) in cases {
            XCTAssertEqual(
                PaddrReadinessResolver.resolve(input).nextAction,
                expectedAction,
                "Unexpected action for \(input)"
            )
        }
    }

    func testReadinessResolverExplainsEveryDisabledOutputState() {
        XCTAssertEqual(
            PaddrReadinessResolver.resolve(
                input(isInitialized: false, canToggleOutput: false)
            ).outputDisabledReason,
            .initializing
        )
        XCTAssertEqual(
            PaddrReadinessResolver.resolve(
                input(isReleasingOutput: true, canToggleOutput: false)
            ).outputDisabledReason,
            .releasingOutputs
        )
        XCTAssertEqual(
            PaddrReadinessResolver.resolve(
                input(canToggleOutput: false)
            ).outputDisabledReason,
            .profileOperation
        )
        XCTAssertNil(PaddrReadinessResolver.resolve(input()).outputDisabledReason)
    }

    func testMenuBarPresentationIncludesRequiredSemantics() {
        let presentation = MenuBarPresentation(
            isEnabled: true,
            isRunning: true,
            isReleasingOutput: false,
            controllerConnected: true,
            puckConnected: true,
            profileName: "Everyday"
        )

        XCTAssertEqual(presentation.outputSummary, "Output: Active")
        XCTAssertEqual(presentation.controllerSummary, "Controller: Connected")
        XCTAssertEqual(presentation.transportSummary, "Transport: Puck connected")
        XCTAssertEqual(presentation.profileSummary, "Profile: Everyday")
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.outputSummary))
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.controllerSummary))
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.transportSummary))
        XCTAssertTrue(presentation.accessibilityLabel.contains(presentation.profileSummary))
        XCTAssertEqual(presentation.tintRole, .active)
        XCTAssertEqual(presentation.symbolName, "hand.point.up.left.fill")

        let waiting = MenuBarPresentation(
            isEnabled: true,
            isRunning: false,
            isReleasingOutput: false,
            controllerConnected: true,
            puckConnected: true,
            profileName: "Everyday"
        )
        XCTAssertEqual(waiting.tintRole, .warning)
        XCTAssertEqual(waiting.symbolName, "hourglass.circle.fill")

        let releasing = MenuBarPresentation(
            isEnabled: false,
            isRunning: false,
            isReleasingOutput: true,
            controllerConnected: true,
            puckConnected: true,
            profileName: "Everyday"
        )
        XCTAssertEqual(releasing.tintRole, .none)
        XCTAssertEqual(releasing.symbolName, "arrow.down.circle.fill")
    }

    private func input(
        isInitialized: Bool = true,
        puckConnected: Bool = true,
        controllerConnected: Bool = true,
        batteryAvailable: Bool = true,
        inputMonitoringGranted: Bool = true,
        accessibilityTrusted: Bool = true,
        isEnabled: Bool = true,
        isRunning: Bool = true,
        isReleasingOutput: Bool = false,
        canToggleOutput: Bool = true
    ) -> PaddrReadinessInput {
        PaddrReadinessInput(
            isInitialized: isInitialized,
            puckConnected: puckConnected,
            controllerConnected: controllerConnected,
            batteryAvailable: batteryAvailable,
            inputMonitoringGranted: inputMonitoringGranted,
            accessibilityTrusted: accessibilityTrusted,
            isEnabled: isEnabled,
            isRunning: isRunning,
            isReleasingOutput: isReleasingOutput,
            canToggleOutput: canToggleOutput
        )
    }

    private func assertColor(
        _ color: Color,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let resolved = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB), file: file, line: line)
        XCTAssertEqual(resolved.redComponent * 255, red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent * 255, green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent * 255, blue, accuracy: 0.01, file: file, line: line)
    }
}
