import AppKit
import SwiftUI
import XCTest

import PaddrAppSupport
@testable import PaddrMenu

@MainActor
final class FamilyConsoleContrastTests: XCTestCase {
    func testProminentControlPairMeetsTextContrast() throws {
        let tint = try resolved(PaddrStyle.controlTint)
        let foreground = try resolved(PaddrStyle.controlForeground)

        XCTAssertGreaterThanOrEqual(foreground.contrastRatio(with: tint), 4.5)
    }

    func testMenuBarSemanticTintsMeetLightAndDarkNonTextContrast() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let lightBackground = SRGBColor(red: 1, green: 1, blue: 1, alpha: 1)
        let darkBackground = try resolved(PaddrStyle.night1)

        for role in [MenuBarTintRole.active, .warning] {
            let dynamicColor = try XCTUnwrap(PaddrMenuBarPalette.color(for: role))
            let lightColor = try resolved(dynamicColor, appearance: lightAppearance)
            let darkColor = try resolved(dynamicColor, appearance: darkAppearance)
            XCTAssertGreaterThanOrEqual(lightColor.contrastRatio(with: lightBackground), 3)
            XCTAssertGreaterThanOrEqual(darkColor.contrastRatio(with: darkBackground), 3)
        }
    }

    func testSelectedZoneBoundaryAndCaptionMeetRenderedContrast() throws {
        let background = try resolved(PaddrStyle.night1)
        let boundary = try resolved(PaddrStyle.selectionBoundary)
        let appearances = [
            PaddrAppearance(colorSchemeContrast: .standard),
            PaddrAppearance(colorSchemeContrast: .increased)
        ]

        for appearance in appearances {
            let topSurface = try resolved(appearance.surface(elevated: true))
                .composited(over: background)
            let bottomSurface = try resolved(appearance.surface(elevated: false))
                .composited(over: background)
            let selectedTop = try resolved(PaddrStyle.selectedZoneFillTop)
                .composited(over: topSurface)
            let selectedBottom = try resolved(PaddrStyle.selectedZoneFillBottom)
                .composited(over: bottomSurface)

            XCTAssertGreaterThanOrEqual(boundary.contrastRatio(with: selectedTop), 3)
            XCTAssertGreaterThanOrEqual(boundary.contrastRatio(with: selectedBottom), 3)
        }

        let captionFill = try resolved(PaddrStyle.selectedZoneCaptionFill)
        let captionForeground = try resolved(PaddrStyle.selectedZoneCaptionForeground)
        XCTAssertGreaterThanOrEqual(captionForeground.contrastRatio(with: captionFill), 4.5)
    }

    func testPointerTapBoundaryMeetsRenderedContrastThroughFullSurfaceStack() throws {
        let background = try resolved(PaddrStyle.night1)
        let boundary = try resolved(PaddrStyle.selectionBoundary)
        let tapFill = try resolved(PaddrStyle.selectedTapFill)
        let appearances = [
            PaddrAppearance(colorSchemeContrast: .standard),
            PaddrAppearance(colorSchemeContrast: .increased)
        ]

        for appearance in appearances {
            let card = try resolved(appearance.surface(elevated: true))
                .composited(over: background)
            let section = try resolved(appearance.surface(elevated: false))
                .composited(over: card)
            for elevated in [false, true] {
                let pad = try resolved(appearance.surface(elevated: elevated))
                    .composited(over: section)
                let renderedTapFill = tapFill.composited(over: pad)
                XCTAssertGreaterThanOrEqual(
                    boundary.contrastRatio(with: renderedTapFill),
                    3,
                    "Pointer boundary failed for elevated=\(elevated), appearance=\(appearance)"
                )
            }
        }
    }

    func testPermissionBordersMeetRenderedNonTextContrast() throws {
        let background = try resolved(PaddrStyle.night1)
        let appearances = [
            PaddrAppearance(colorSchemeContrast: .standard),
            PaddrAppearance(colorSchemeContrast: .increased)
        ]

        for appearance in appearances {
            let card = try resolved(appearance.surface(elevated: true))
                .composited(over: background)
            for semanticColor in [PaddrStyle.successGreen, PaddrStyle.cautionAmber] {
                let semantic = try resolved(semanticColor)
                let tile = semantic
                    .withAlpha(PaddrStyle.permissionFillOpacity)
                    .composited(over: card)
                let border = semantic
                    .withAlpha(
                        appearance.strokeOpacity(PaddrStyle.permissionStrokeOpacity)
                    )
                    .composited(over: tile)

                XCTAssertGreaterThanOrEqual(border.contrastRatio(with: tile), 3)
            }
        }
    }

    func testPermissionSuccessTextMeetsRenderedContrast() throws {
        let background = try resolved(PaddrStyle.night1)
        let success = try resolved(PaddrStyle.successGreen)
        let successText = try resolved(PaddrStyle.successText)
        let appearances = [
            PaddrAppearance(colorSchemeContrast: .standard),
            PaddrAppearance(colorSchemeContrast: .increased)
        ]

        for appearance in appearances {
            let card = try resolved(appearance.surface(elevated: true))
                .composited(over: background)
            let tile = success
                .withAlpha(PaddrStyle.permissionFillOpacity)
                .composited(over: card)
            XCTAssertGreaterThanOrEqual(successText.contrastRatio(with: tile), 4.5)
        }
    }

    func testIncreasedContrastStrengthensSurfaceFillsAndStrokes() throws {
        let standard = PaddrAppearance(colorSchemeContrast: .standard)
        let increased = PaddrAppearance(colorSchemeContrast: .increased)

        XCTAssertEqual(try resolved(standard.surface(elevated: false)).alpha, 0.05, accuracy: 0.001)
        XCTAssertEqual(try resolved(standard.surface(elevated: true)).alpha, 0.08, accuracy: 0.001)
        XCTAssertEqual(try resolved(standard.surfaceStroke).alpha, 0.10, accuracy: 0.001)
        XCTAssertEqual(try resolved(increased.surface(elevated: false)).alpha, 0.09, accuracy: 0.001)
        XCTAssertEqual(try resolved(increased.surface(elevated: true)).alpha, 0.14, accuracy: 0.001)
        XCTAssertEqual(try resolved(increased.surfaceStroke).alpha, 0.28, accuracy: 0.001)
        XCTAssertGreaterThan(increased.strokeWidth, standard.strokeWidth)
    }

    func testReadyStatusUsesSuccessSemantic() throws {
        let ready = try resolved(StatusBadgeState.ready.color)
        let readyText = try resolved(StatusBadgeState.ready.textColor)
        let successTone = try resolved(PaddrStyle.successGreen)
        let successText = try resolved(PaddrStyle.successText)
        let background = try resolved(PaddrStyle.night1)

        assertEqual(ready, successTone)
        assertEqual(readyText, successText)
        XCTAssertGreaterThanOrEqual(readyText.contrastRatio(with: background), 4.5)
    }

    func testCriticalStatusUsesErrorSemantic() throws {
        let critical = try resolved(StatusBadgeState.critical.color)
        let criticalText = try resolved(StatusBadgeState.critical.textColor)
        let errorTone = try resolved(PaddrStyle.errorText)
        let background = try resolved(PaddrStyle.night1)

        assertEqual(critical, errorTone)
        assertEqual(criticalText, errorTone)
        XCTAssertGreaterThanOrEqual(criticalText.contrastRatio(with: background), 4.5)
    }

    private func resolved(
        _ color: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SRGBColor {
        let nsColor = try XCTUnwrap(
            NSColor(color).usingColorSpace(.sRGB),
            file: file,
            line: line
        )
        return SRGBColor(
            red: nsColor.redComponent,
            green: nsColor.greenComponent,
            blue: nsColor.blueComponent,
            alpha: nsColor.alphaComponent
        )
    }

    private func resolved(
        _ color: NSColor,
        appearance: NSAppearance? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SRGBColor {
        var resolvedColor: NSColor?
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                resolvedColor = color.usingColorSpace(.sRGB)
            }
        } else {
            resolvedColor = color.usingColorSpace(.sRGB)
        }
        let color = try XCTUnwrap(resolvedColor, file: file, line: line)
        return SRGBColor(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }

    private func assertEqual(
        _ lhs: SRGBColor,
        _ rhs: SRGBColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.red, rhs.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.green, rhs.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.blue, rhs.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.alpha, rhs.alpha, accuracy: 0.001, file: file, line: line)
    }
}

private struct SRGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    func withAlpha(_ alpha: Double) -> Self {
        Self(red: red, green: green, blue: blue, alpha: CGFloat(alpha))
    }

    func composited(over background: Self) -> Self {
        let outputAlpha = alpha + background.alpha * (1 - alpha)
        guard outputAlpha > 0 else {
            return Self(red: 0, green: 0, blue: 0, alpha: 0)
        }
        return Self(
            red: (red * alpha + background.red * background.alpha * (1 - alpha)) / outputAlpha,
            green: (green * alpha + background.green * background.alpha * (1 - alpha)) / outputAlpha,
            blue: (blue * alpha + background.blue * background.alpha * (1 - alpha)) / outputAlpha,
            alpha: outputAlpha
        )
    }

    func contrastRatio(with other: Self) -> CGFloat {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var relativeLuminance: CGFloat {
        0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
    }

    private static func linearized(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
