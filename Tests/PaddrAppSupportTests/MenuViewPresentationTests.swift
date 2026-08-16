import AppKit
import Dispatch
import SwiftUI
import XCTest

import PaddrAppSupport
@testable import PaddrMenu
import PaddrCore

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
        XCTAssertEqual(PaddrStyle.Metrics.guideWindowSize, NSSize(width: 680, height: 430))
        XCTAssertEqual(PaddrStyle.Metrics.minimumGuideWindowSize, NSSize(width: 560, height: 430))

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.Metrics.guideWindowSize)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.guideWindowSize.height,
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
            PaddrStyle.Metrics.row + (2 * PaddrStyle.Spacing.s3)
        )
        XCTAssertLessThan(collapsedHeight, expandedHeight)
    }

    /// Each case sets every lower-precedence flag as well, so it fails if the resolver
    /// reorders any adjacent pair.
    func testPaddrControlStateResolvesTheDocumentedPrecedenceOrder() {
        XCTAssertEqual(
            PaddrControlState(
                isEnabled: false,
                isProminent: true,
                isSelected: true,
                isPressed: true,
                isHovering: true
            ).row,
            .disabled
        )
        XCTAssertEqual(
            PaddrControlState(
                isProminent: true,
                isSelected: true,
                isPressed: true,
                isHovering: true
            ).row,
            .prominent
        )
        XCTAssertEqual(
            PaddrControlState(isSelected: true, isPressed: true, isHovering: true).row,
            .selected
        )
        // Press and hover are not rows at all, so a control that is only being pressed or
        // hovered is still at rest and its feedback comes from the additive overlay.
        XCTAssertEqual(PaddrControlState(isPressed: true, isHovering: true).row, .rest)
        XCTAssertEqual(PaddrControlState(isHovering: true).row, .rest)
        XCTAssertEqual(PaddrControlState().row, .rest)
    }

    func testPaddrControlStateResolvesEveryInputCombinationToOneRow() {
        // The documented order, expressed as data rather than as a second copy of the
        // resolver's control flow.
        let precedence: [(row: PaddrControlRow, applies: (PaddrControlState) -> Bool)] = [
            (.disabled, { !$0.isEnabled }),
            (.prominent, \.isProminent),
            (.selected, \.isSelected)
        ]
        let differentiating = PaddrAppearance(differentiateWithoutColor: true)

        for isEnabled in [true, false] {
            for isProminent in [false, true] {
                for isSelected in [false, true] {
                    for isPressed in [false, true] {
                        for isHovering in [false, true] {
                            for isFocused in [false, true] {
                                let state = PaddrControlState(
                                    isEnabled: isEnabled,
                                    isProminent: isProminent,
                                    isSelected: isSelected,
                                    isPressed: isPressed,
                                    isHovering: isHovering,
                                    isFocused: isFocused
                                )
                                let label = "\(state)"
                                XCTAssertEqual(
                                    state.row,
                                    precedence.first { $0.applies(state) }?.row ?? .rest,
                                    label
                                )

                                // Focus is additive: it never changes which row won, and a
                                // disabled control never shows a ring.
                                var unfocused = state
                                unfocused.isFocused = false
                                XCTAssertEqual(state.row, unfocused.row, label)
                                XCTAssertEqual(state.showsFocusRing, isFocused && isEnabled, label)

                                // The row is role and selection only, so neither interaction
                                // flag can move it — which is why neither can be swallowed.
                                var withoutInteraction = state
                                withoutInteraction.isPressed = false
                                withoutInteraction.isHovering = false
                                XCTAssertEqual(state.row, withoutInteraction.row, label)

                                // A press is always visible, and always more than a hover:
                                // the overlay applies over every row, and only a disabled
                                // control suppresses it.
                                XCTAssertEqual(
                                    state.interactionOverlay.isActive,
                                    isEnabled && (isPressed || isHovering),
                                    label
                                )
                                if isPressed && isEnabled {
                                    var hoverOnly = state
                                    hoverOnly.isPressed = false
                                    hoverOnly.isHovering = true
                                    XCTAssertGreaterThan(
                                        state.interactionOverlay.fillOpacity,
                                        hoverOnly.interactionOverlay.fillOpacity,
                                        "A press must be visible in \(label)"
                                    )
                                }

                                // Selection is never colour-only, and the mark tracks
                                // selection rather than the winning row.
                                XCTAssertEqual(
                                    state.showsSelectionMark(in: differentiating),
                                    isSelected && isEnabled,
                                    label
                                )
                                XCTAssertFalse(
                                    state.showsSelectionMark(in: PaddrAppearance()),
                                    label
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// The class invariant behind this slice's two suppression defects — a prominent button
    /// that showed no press, then a prominent button that showed no hover. Both are one bug:
    /// an interaction flag swallowed by a row that outranks it. Stated over all 64
    /// combinations as "removing the flag must change what is drawn", rather than per row,
    /// because fixing it one row at a time is what let the second instance through.
    func testNoInteractionFlagIsSwallowedByTheRowThatOutranksIt() {
        /// What the surface paints, minus the ring: the row supplies the base fill, stroke,
        /// and label, and the overlay is composited over them.
        struct Drawn: Equatable {
            let row: PaddrControlRow
            let overlay: PaddrInteractionOverlay

            init(_ state: PaddrControlState) {
                row = state.row
                overlay = state.interactionOverlay
            }
        }

        for isEnabled in [true, false] {
            for isProminent in [false, true] {
                for isSelected in [false, true] {
                    for isPressed in [false, true] {
                        for isHovering in [false, true] {
                            for isFocused in [false, true] {
                                let state = PaddrControlState(
                                    isEnabled: isEnabled,
                                    isProminent: isProminent,
                                    isSelected: isSelected,
                                    isPressed: isPressed,
                                    isHovering: isHovering,
                                    isFocused: isFocused
                                )
                                let label = "\(state)"
                                var withoutHover = state
                                withoutHover.isHovering = false
                                var withoutPress = state
                                withoutPress.isPressed = false
                                var withoutFocus = state
                                withoutFocus.isFocused = false

                                guard isEnabled else {
                                    // A disabled control does not react: hover, press, and
                                    // focus are all suppressed, and dropping any of them
                                    // changes nothing that is drawn.
                                    XCTAssertEqual(state.interactionOverlay, .none, label)
                                    XCTAssertFalse(state.showsFocusRing, label)
                                    XCTAssertEqual(Drawn(state), Drawn(withoutHover), label)
                                    XCTAssertEqual(Drawn(state), Drawn(withoutPress), label)
                                    XCTAssertEqual(
                                        state.showsFocusRing,
                                        withoutFocus.showsFocusRing,
                                        label
                                    )
                                    continue
                                }

                                if isPressed {
                                    XCTAssertNotEqual(
                                        Drawn(state),
                                        Drawn(withoutPress),
                                        "A press is invisible in \(label)"
                                    )
                                }
                                // Hover is visible on every row too. Its one exemption is a
                                // press, which is strictly stronger and always implies it.
                                if isHovering && !isPressed {
                                    XCTAssertNotEqual(
                                        Drawn(state),
                                        Drawn(withoutHover),
                                        "A hover is invisible in \(label)"
                                    )
                                }
                                XCTAssertEqual(state.showsFocusRing, isFocused, label)

                                // The overlay's own terms, stated exactly and over every
                                // row: hover and press share the activation, a press deepens
                                // the fill on top of it, and selection deepens the stroke
                                // while it is active.
                                let overlay = state.interactionOverlay
                                if isPressed || isHovering {
                                    XCTAssertEqual(
                                        overlay.fillOpacity,
                                        isPressed ? 0.075 : 0.050,
                                        accuracy: 0.0001,
                                        label
                                    )
                                    XCTAssertEqual(
                                        overlay.strokeOpacity,
                                        isSelected ? 0.44 : 0.36,
                                        accuracy: 0.0001,
                                        label
                                    )
                                } else {
                                    XCTAssertEqual(overlay, .none, label)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// `focusEffectDisabled()` removes the system ring, so this ring is the only focus
    /// indication a Paddr button has. Drawing it in accent on the prominent row — whose fill
    /// is solid accent — left every primary button in the app (`Save & Apply`, the guide's
    /// `Next` and `Get Started`, both permission `Request` buttons) with no focus indication
    /// at all. The ring is inset rather than outset, so it must contrast with its own fill.
    func testTheFocusRingContrastsWithEveryRowsOwnFill() {
        for (expected, state) in Self.rowStates {
            XCTAssertEqual(state.row, expected)
            let surface = PaddrControlSurface(state: state)
            XCTAssertNotEqual(
                surface.focusRingColor,
                surface.fillColor,
                "The focus ring is invisible on the \(expected) row"
            )
        }

        // The prominent ring was a fixed white, which held only while the accent was a fixed
        // blue. It is now the derived on-accent colour — the same one the prominent label
        // takes — because a white ring on a yellow accent is this defect a third time.
        // `testTheProminentLabelAndRingClearBodyContrastOnEveryMacOSAccent` is what pins the
        // ratio; this pins that the ring and the label are the same derivation.
        XCTAssertEqual(
            PaddrControlSurface(state: PaddrControlState(isProminent: true)).focusRingColor,
            PaddrStyle.onAccent
        )
        XCTAssertEqual(
            PaddrControlSurface(state: PaddrControlState()).focusRingColor,
            PaddrStyle.accent
        )
    }

    /// Every row strokes, so the interaction overlay's stroke term reaches every row. The
    /// prominent row's stroke was `nil`, which made hover and press on a primary button read
    /// through the fill delta alone — the suppression family this slice already closed twice,
    /// arriving through the stroke instead of through the row resolver.
    func testTheProminentRowStrokesSoTheOverlayReachesIt() {
        for (row, state) in Self.rowStates {
            XCTAssertEqual(state.row, row)
            XCTAssertNotNil(
                PaddrControlSurface(state: state).strokeColor,
                "The \(row) row draws no stroke, so the overlay's stroke term is inert on it"
            )
        }

        let prominent = PaddrControlSurface(state: PaddrControlState(isProminent: true))
        XCTAssertEqual(prominent.strokeColor, PaddrStyle.onAccentStroke)
        XCTAssertEqual(prominent.resolvedStrokeOpacity, 0.6, accuracy: 0.0001)
        // The base leaves headroom for the overlay on purpose: at full opacity the clamp
        // would swallow the term and reinstate the defect above.
        XCTAssertEqual(
            PaddrControlSurface(state: PaddrControlState(isProminent: true, isHovering: true))
                .resolvedStrokeOpacity,
            0.96,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            PaddrControlSurface(state: PaddrControlState(isProminent: true, isPressed: true))
                .resolvedStrokeOpacity,
            prominent.resolvedStrokeOpacity
        )
    }

    /// Status and label text is derived from the viewer's accent, so it has to clear 4.5:1
    /// for an accent this machine may never have selected. Driven over the whole macOS
    /// accent set in both appearances rather than over the one accent the test host runs
    /// with.
    func testAccentTextClearsBodyContrastOnEveryMacOSAccent() throws {
        for isDark in [false, true] {
            let background = try resolvedSRGB(.windowBackgroundColor, isDark: isDark)
            for (name, systemColor) in Self.macOSAccents {
                let accent = try resolvedSRGB(systemColor, isDark: isDark)
                let derived = PaddrAccentPalette.text(from: accent, on: background)
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(derived, background),
                    4.5,
                    "\(name)/\(isDark ? "dark" : "light") status text misses body contrast"
                )
            }
        }
    }

    /// White on an accent fill is the assumption that a fixed blue accent permitted. It does
    /// not survive the palette: white reads 1.51:1 on yellow and 3.52:1 on the stock blue,
    /// and in fact clears 4.5:1 on none of the eight. The label and the focus ring share the
    /// derivation, so both are asserted here.
    func testTheProminentLabelAndRingClearBodyContrastOnEveryMacOSAccent() throws {
        // Fail-before: the colour this row used to draw, against the accent that breaks it
        // hardest and against the default one.
        let yellow = try resolvedSRGB(.systemYellow, isDark: false)
        let blue = try resolvedSRGB(.systemBlue, isDark: false)
        XCTAssertLessThan(contrastRatio(.white, yellow), 4.5)
        XCTAssertLessThan(contrastRatio(.white, blue), 4.5)

        for isDark in [false, true] {
            for (name, systemColor) in Self.macOSAccents {
                let accent = try resolvedSRGB(systemColor, isDark: isDark)
                let label = PaddrAccentPalette.onAccentLabel(for: accent)
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(label, accent),
                    4.5,
                    "\(name)/\(isDark ? "dark" : "light") prominent label misses body contrast"
                )
            }
        }
    }

    /// The prominent stroke is a non-text boundary, so it targets 3:1 — and the rim that has
    /// to clear it is the composited one, drawn at the base opacity over the accent fill,
    /// not the colour in isolation.
    func testTheProminentStrokeClearsNonTextContrastOnEveryMacOSAccent() throws {
        let opacity = PaddrStyle.prominentStrokeOpacity
        for isDark in [false, true] {
            for (name, systemColor) in Self.macOSAccents {
                let accent = try resolvedSRGB(systemColor, isDark: isDark)
                let stroke = PaddrAccentPalette.onAccentStroke(for: accent, drawnAt: opacity)
                let label = "\(name)/\(isDark ? "dark" : "light")"
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(stroke, accent),
                    3.0,
                    "\(label) prominent stroke misses non-text contrast"
                )
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(composite(stroke, over: accent, opacity: opacity), accent),
                    3.0,
                    "\(label) prominent rim misses non-text contrast as drawn"
                )
            }
        }
    }

    /// One state per case of `PaddrControlRow`; a case added without a partner here fails the
    /// row assertion at every use site.
    private static let rowStates: [(PaddrControlRow, PaddrControlState)] = [
        (.rest, PaddrControlState()),
        (.selected, PaddrControlState(isSelected: true)),
        (.prominent, PaddrControlState(isProminent: true)),
        (.disabled, PaddrControlState(isEnabled: false))
    ]

    /// The eight accents System Settings offers, as the system colours they are drawn from.
    /// Taken as system colours rather than as literals so the set tracks Apple's palette,
    /// and resolved per appearance because the palette differs between the two.
    private static let macOSAccents: [(String, NSColor)] = [
        ("blue", .systemBlue),
        ("purple", .systemPurple),
        ("pink", .systemPink),
        ("red", .systemRed),
        ("orange", .systemOrange),
        ("yellow", .systemYellow),
        ("green", .systemGreen),
        ("graphite", .systemGray)
    ]

    private func resolvedSRGB(_ color: NSColor, isDark: Bool) throws -> NSColor {
        let appearance = try XCTUnwrap(NSAppearance(named: isDark ? .darkAqua : .aqua))
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(resolved)
    }

    /// WCAG 2.1 contrast, implemented here rather than borrowed from `PaddrAccentPalette`:
    /// a derivation checked with its own arithmetic proves nothing about the ratio.
    private func contrastRatio(_ one: NSColor, _ other: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
            func channel(_ component: CGFloat) -> Double {
                let value = Double(component)
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(srgb.redComponent)
                + 0.7152 * channel(srgb.greenComponent)
                + 0.0722 * channel(srgb.blueComponent)
        }
        let first = luminance(one)
        let second = luminance(other)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Source-over compositing of a partly transparent stroke on an opaque fill.
    private func composite(_ source: NSColor, over destination: NSColor, opacity: Double) -> NSColor {
        guard
            let source = source.usingColorSpace(.sRGB),
            let destination = destination.usingColorSpace(.sRGB)
        else { return destination }
        let alpha = CGFloat(opacity)
        func mix(_ over: CGFloat, _ under: CGFloat) -> CGFloat {
            (over * alpha) + (under * (1 - alpha))
        }
        return NSColor(
            srgbRed: mix(source.redComponent, destination.redComponent),
            green: mix(source.greenComponent, destination.greenComponent),
            blue: mix(source.blueComponent, destination.blueComponent),
            alpha: 1
        )
    }

    /// The overlay's stroke term is added to the base rather than replacing it, so a
    /// selected control under the pointer sums past 1 — an opacity that means nothing and
    /// would make the standard path differ from the increased-contrast one by accident. The
    /// sum is clamped, and only clamped: every other combination is the plain addition.
    func testTheInteractionOverlayAddsToTheBaseStrokeAndClampsAtFullOpacity() {
        func resolved(_ state: PaddrControlState) -> Double {
            PaddrControlSurface(state: state).resolvedStrokeOpacity
        }

        XCTAssertEqual(resolved(PaddrControlState()), 0.50, accuracy: 0.0001)
        XCTAssertEqual(resolved(PaddrControlState(isHovering: true)), 0.86, accuracy: 0.0001)
        XCTAssertEqual(resolved(PaddrControlState(isPressed: true)), 0.86, accuracy: 0.0001)
        XCTAssertEqual(resolved(PaddrControlState(isSelected: true)), 0.70, accuracy: 0.0001)
        XCTAssertEqual(
            resolved(PaddrControlState(isSelected: true, isHovering: true)),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            resolved(PaddrControlState(isSelected: true, isPressed: true, isHovering: true)),
            1,
            accuracy: 0.0001
        )
        // A disabled control reacts to nothing, so its stroke is the base alone.
        XCTAssertEqual(
            resolved(PaddrControlState(isEnabled: false, isPressed: true, isHovering: true)),
            0.50 * 0.4,
            accuracy: 0.0001
        )
    }

    /// A custom `ButtonStyle` renders no `NSControl`, so the row-height assertions elsewhere
    /// in this file cannot see a button at all. The height is asserted on the hosted
    /// geometry directly, and exactly, rather than as containment.
    func testEveryButtonRoleRendersAtTheButtonHeight() {
        // `control` is the in-row height and stays 24 so a settings-row control keeps fitting
        // `row`; `button` is LimitlessQuilter's standard control height, used only by the
        // button family, none of which sits inside a settings row.
        XCTAssertEqual(PaddrStyle.Metrics.control, 24)
        XCTAssertEqual(PaddrStyle.Metrics.button, 38)
        XCTAssertEqual(PaddrStyle.Radius.control, 7)
        XCTAssertEqual(PaddrStyle.Radius.card, 14)
        XCTAssertEqual(PaddrStyle.Metrics.controlHorizontalPadding, 10)
        // The row-fitting obligation belongs to the in-row height, which is the one every
        // `PaddrSettingsRow` control is laid out at.
        XCTAssertLessThanOrEqual(PaddrStyle.Metrics.control, PaddrStyle.Metrics.row)

        for role in [PaddrButtonRole.primary, .secondary, .icon] {
            let hostingView = NSHostingView(
                rootView: Button("Request", systemImage: "gearshape", action: {})
                    .paddrActionButton(role)
            )
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertEqual(
                hostingView.fittingSize.height,
                PaddrStyle.Metrics.button,
                accuracy: 0.5,
                "\(role) does not render at the button height"
            )
            if role == .icon {
                XCTAssertEqual(
                    hostingView.fittingSize.width,
                    PaddrStyle.Metrics.button,
                    accuracy: 0.5,
                    "The icon role must be square at the button height"
                )
            }
        }
    }

    /// The slice-1 adaptive matrix, extended to the button family. Height is the property
    /// that an adaptive override can silently break — a heavier stroke or an opaque fill
    /// that changes layout — so it is asserted per cell rather than left to containment.
    func testAdaptiveMatrixKeepsEveryButtonRoleAtTheButtonHeight() {
        for role in [PaddrButtonRole.primary, .secondary, .icon] {
            for colorScheme in [ColorScheme.light, .dark] {
                for contrast in [ColorSchemeContrast.standard, .increased] {
                    for reduceTransparency in [false, true] {
                        for differentiateWithoutColor in [false, true] {
                            let view = Button("Request", systemImage: "gearshape", action: {})
                                .paddrActionButton(role)
                                .environment(\.colorScheme, colorScheme)
                                .environment(\._colorSchemeContrast, contrast)
                                .environment(
                                    \._accessibilityReduceTransparency,
                                    reduceTransparency
                                )
                                .environment(
                                    \._accessibilityDifferentiateWithoutColor,
                                    differentiateWithoutColor
                                )
                            let label = """
                                \(role)/\(colorScheme)/\(contrast)/\
                                reduceTransparency:\(reduceTransparency)/\
                                differentiateWithoutColor:\(differentiateWithoutColor)
                                """
                            let hostingView = NSHostingView(rootView: view)
                            hostingView.layoutSubtreeIfNeeded()
                            let fitted = hostingView.fittingSize
                            XCTAssertTrue(fitted.width.isFinite, label)
                            XCTAssertGreaterThan(fitted.width, 0, label)
                            XCTAssertEqual(
                                fitted.height,
                                PaddrStyle.Metrics.button,
                                accuracy: 0.5,
                                label
                            )
                        }
                    }
                }
            }
        }
    }

    /// Selection must not be carried by colour alone. The mark is a real layout change, so
    /// the surface is wider under Differentiate Without Colour than without it.
    func testSelectedSurfaceCarriesItsMarkUnderDifferentiateWithoutColor() {
        func selectedWidth(differentiateWithoutColor: Bool) -> CGFloat {
            let hostingView = NSHostingView(
                rootView: Text(verbatim: "Scroll")
                    .paddrControlSurface(PaddrControlState(isSelected: true))
                    .environment(
                        \._accessibilityDifferentiateWithoutColor,
                        differentiateWithoutColor
                    )
            )
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.width
        }

        let plain = selectedWidth(differentiateWithoutColor: false)
        let marked = selectedWidth(differentiateWithoutColor: true)
        XCTAssertGreaterThan(
            marked,
            plain + PaddrStyle.Spacing.s1,
            "The selected surface carries no additional mark under Differentiate Without Colour"
        )

        // An unselected surface gains nothing, so the mark is selection and not decoration.
        let unselected = NSHostingView(
            rootView: Text(verbatim: "Scroll")
                .paddrControlSurface(PaddrControlState())
                .environment(\._accessibilityDifferentiateWithoutColor, true)
        )
        unselected.layoutSubtreeIfNeeded()
        XCTAssertEqual(unselected.fittingSize.width, plain, accuracy: 0.5)
    }

    /// `focusEffectDisabled()` must suppress the system focus effect without removing the
    /// button from the keyboard focus order. SwiftUI's key-view-loop participant is the
    /// probe for the second half; `focusable(false)` is the negative control, so a renamed
    /// or vanished participant fails this test rather than passing it vacuously.
    func testSuppressingTheSystemFocusEffectKeepsButtonsInTheKeyViewLoop() {
        func viewTypeNames(_ view: some View) -> [String] {
            let hostingView = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
            hostingView.layoutSubtreeIfNeeded()
            window.recalculateKeyViewLoop()
            return descendants(of: NSView.self, in: hostingView)
                .map { String(describing: type(of: $0)) }
        }
        func keyViewProxies(_ names: [String]) -> Int {
            names.filter { $0.contains("KeyViewProxy") }.count
        }
        func focusRings(_ names: [String]) -> Int {
            names.filter { $0.contains("FocusRingView") }.count
        }

        let stock = viewTypeNames(Button("Stock", action: {}).buttonStyle(.bordered))
        let paddr = viewTypeNames(Button("Paddr", action: {}).paddrActionButton(.secondary))
        let unfocusable = viewTypeNames(
            Button("Unfocusable", action: {}).paddrActionButton(.secondary).focusable(false)
        )

        XCTAssertEqual(keyViewProxies(stock), 1, "Baseline: a stock button joins the key-view loop")
        XCTAssertEqual(
            keyViewProxies(paddr),
            keyViewProxies(stock),
            "A Paddr button left the keyboard focus order: \(paddr)"
        )
        XCTAssertEqual(
            keyViewProxies(unfocusable),
            0,
            "Negative control: an unfocusable button must not join the loop"
        )

        XCTAssertEqual(focusRings(stock), 1, "Baseline: a stock button draws the system effect")
        XCTAssertEqual(
            focusRings(paddr),
            0,
            "The system focus effect is not suppressed, so it doubles the Paddr ring: \(paddr)"
        )
    }

    func testPaddrAppearanceResolvesEveryAdaptiveCombination() {
        for reduceTransparency in [false, true] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                for differentiateWithoutColor in [false, true] {
                    for reduceMotion in [false, true] {
                        let appearance = PaddrAppearance(
                            reduceTransparency: reduceTransparency,
                            colorSchemeContrast: contrast,
                            differentiateWithoutColor: differentiateWithoutColor,
                            reduceMotion: reduceMotion
                        )
                        let increased = contrast == .increased
                        XCTAssertEqual(appearance.usesOpaqueFallback, reduceTransparency)
                        XCTAssertEqual(appearance.hasIncreasedContrast, increased)
                        XCTAssertEqual(appearance.usesShapeDifferentiation, differentiateWithoutColor)
                        XCTAssertEqual(appearance.reducesMotion, reduceMotion)
                        XCTAssertEqual(appearance.strokeWidth, increased ? 1.5 : 1)
                        XCTAssertEqual(appearance.strokeOpacity(0.46), increased ? 1 : 0.46)
                        XCTAssertEqual(appearance.strokeOpacity(0.18), increased ? 1 : 0.18)
                        XCTAssertEqual(appearance.animation(.default) == nil, reduceMotion)
                        XCTAssertNil(appearance.animation(nil))
                    }
                }
            }
        }
    }

    func testSettingsRowControlsStayWithinTheSharedRowHeightInEveryPadMode() {
        for mode in PadMode.allCases {
            for layout in PadZoneLayout.allCases {
                var configuration = PadConfiguration(mode: mode)
                configuration.zoneLayout = layout
                let hostingView = NSHostingView(
                    rootView: PadConfigurationView(
                        side: .left,
                        configuration: .constant(configuration),
                        initiallyExpanded: true
                    )
                    .frame(width: PaddrStyle.padColumnWidth)
                )
                hostingView.frame = NSRect(
                    origin: .zero,
                    size: NSSize(
                        width: PaddrStyle.padColumnWidth,
                        height: PaddrStyle.padConfigurationCardHeight
                    )
                )
                hostingView.layoutSubtreeIfNeeded()

                for control in descendants(of: NSControl.self, in: hostingView) {
                    XCTAssertLessThanOrEqual(
                        control.bounds.height,
                        PaddrStyle.Metrics.row + 0.5,
                        "\(type(of: control)) in \(mode)/\(layout) is taller than the row family"
                    )
                    assertControlFits(control, in: hostingView)
                }
            }
        }
    }

    /// A SwiftUI `Slider` renders no `NSControl` descendant on this SDK, so the switch is
    /// the probe that is actually reachable through the `descendants(of:)` seam.
    func testSettingsRowCentersItsControlInTheSharedRowHeight() throws {
        let row = PaddrSettingsRow(title: "Track pointer", systemImage: "scope") {
            Toggle("Track pointer", isOn: .constant(true))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .frame(width: PaddrStyle.padColumnWidth)
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.padColumnWidth,
                height: hostingView.fittingSize.height
            )
        )
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.bounds.height,
            PaddrStyle.Metrics.row + (2 * PaddrStyle.Spacing.s1),
            accuracy: 0.5
        )
        let toggle = try XCTUnwrap(firstDescendant(of: NSControl.self, in: hostingView))
        let frame = toggle.convert(toggle.bounds, to: hostingView)
        XCTAssertLessThanOrEqual(frame.height, PaddrStyle.Metrics.row + 0.5)
        XCTAssertEqual(frame.midY, hostingView.bounds.midY, accuracy: 0.5)
    }

    func testSettingsGroupAddsItsSeparatingDividerOnlyWhenDeclared() {
        func groupHeight(showsLeadingDivider: Bool) -> CGFloat {
            let group = PaddrSettingsGroup(showsLeadingDivider: showsLeadingDivider) {
                PaddrSettingsRow(title: "Sensitivity", systemImage: "speedometer") {
                    Slider(value: .constant(0.5), in: 0...1)
                        .frame(width: PaddrStyle.Width.control)
                }
            }
            .frame(width: PaddrStyle.padColumnWidth)
            let hostingView = NSHostingView(rootView: group)
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.height
        }

        XCTAssertGreaterThan(
            groupHeight(showsLeadingDivider: true),
            groupHeight(showsLeadingDivider: false)
        )
    }

    /// The inspector column is the binding constraint on the width scale, and overrunning it
    /// fails silently in two ways a bounds check cannot see: `ViewThatFits` drops the row
    /// into its stacked fallback, and a starved label wraps mid-word. Both are asserted on
    /// the geometry directly.
    func testPickerRowFitsItsInlineBranchInsideTheInspectorColumn() {
        XCTAssertLessThanOrEqual(
            PaddrStyle.Width.labelColumn + PaddrStyle.Spacing.s3 + PaddrStyle.Width.control,
            PaddrStyle.zoneInspectorWidth,
            "A picker row's inline branch must fit the inspector column"
        )
        // The area-layout row is Text + HStack spacing + Spacer(minLength:) + HStack spacing
        // + picker, so it spends three `s3` gaps, not one. At `controlWide` its label was
        // left 30pt and wrapped mid-word.
        let modeLabel = NSHostingView(
            rootView: Text(LocalizedStringResource("Mode")).paddrTypography(.sectionLabel)
        )
        modeLabel.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            modeLabel.fittingSize.width,
            PaddrStyle.zoneInspectorWidth
                - PaddrStyle.Width.controlMedium
                - (3 * PaddrStyle.Spacing.s3),
            "The area-layout row starves its label, which then wraps mid-word"
        )

        let row = PaddrSettingsRow(title: "Action", systemImage: "keyboard") {
            OutputBindingPicker(
                selection: .constant("Up arrow"),
                width: PaddrStyle.Width.control
            )
        }
        .frame(width: PaddrStyle.zoneInspectorWidth)
        let hostingView = NSHostingView(rootView: row)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.row + (2 * PaddrStyle.Spacing.s1),
            accuracy: 0.5,
            "The row fell back to the stacked branch inside the inspector column"
        )
    }

    /// The public `colorSchemeContrast`, `accessibilityReduceTransparency`, and
    /// `accessibilityDifferentiateWithoutColor` values are read-only, so the hosted matrix
    /// drives them through their underscore-prefixed writable key paths. `PaddrAppearance`'s
    /// own resolution of the same inputs is proved separately by
    /// `testPaddrAppearanceResolvesEveryAdaptiveCombination`.
    func testAdaptiveMatrixKeepsSurfacesFiniteAndControlsInsideTheHost() {
        for colorScheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                for reduceTransparency in [false, true] {
                    for differentiateWithoutColor in [false, true] {
                        let view = adaptiveMatrixSubject
                            .environment(\.colorScheme, colorScheme)
                            .environment(\._colorSchemeContrast, contrast)
                            .environment(\._accessibilityReduceTransparency, reduceTransparency)
                            .environment(
                                \._accessibilityDifferentiateWithoutColor,
                                differentiateWithoutColor
                            )

                        let label = """
                            \(colorScheme)/\(contrast)/\
                            reduceTransparency:\(reduceTransparency)/\
                            differentiateWithoutColor:\(differentiateWithoutColor)
                            """
                        let hostingView = NSHostingView(rootView: view)
                        let fitted = hostingView.fittingSize
                        XCTAssertTrue(fitted.width.isFinite, label)
                        XCTAssertTrue(fitted.height.isFinite, label)
                        XCTAssertGreaterThan(fitted.height, 0, label)

                        hostingView.frame = NSRect(
                            origin: .zero,
                            size: NSSize(width: PaddrStyle.padColumnWidth, height: fitted.height)
                        )
                        hostingView.layoutSubtreeIfNeeded()
                        for control in descendants(of: NSControl.self, in: hostingView) {
                            assertControlFits(control, in: hostingView)
                        }
                    }
                }
            }
        }
    }

    /// The three surfaces this slice moved onto `PaddrAppearance`: the card chrome, the
    /// status chip, and the permission row.
    private var adaptiveMatrixSubject: some View {
        VStack(spacing: PaddrStyle.Spacing.s3) {
            StatusCell(
                title: LocalizedStringResource("Output"),
                value: LocalizedStringResource("Active"),
                systemImage: "wave.3.right.circle.fill",
                state: .active
            )
            PermissionTile(
                title: LocalizedStringResource("Accessibility"),
                detail: LocalizedStringResource("Sends mapped mouse, scroll, and keyboard input."),
                isGranted: false,
                requestAction: {},
                settingsAction: {}
            )
            PadConfigurationView(
                side: .left,
                configuration: .constant(PaddrConfiguration.default.left),
                initiallyExpanded: true
            )
        }
        .frame(width: PaddrStyle.padColumnWidth)
        .background { PanelBackgroundView() }
    }

    func testPointerTrackingToggleReflectsDefaultsAndLegacyBindingAtRadiusZero() throws {
        let defaultView = PadConfigurationView(
            side: .right,
            configuration: .constant(PadConfiguration(mode: .mouse)),
            initiallyExpanded: true
        )
        .frame(width: PaddrStyle.Metrics.minimumWindowSize.width - (2 * PaddrStyle.Spacing.s4))
        let defaultHostingView = NSHostingView(rootView: defaultView)
        defaultHostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.Metrics.minimumWindowSize.width - (2 * PaddrStyle.Spacing.s4),
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
            in: NSSize(width: PaddrStyle.Metrics.minimumWindowSize.width, height: 400)
        )
        XCTAssertLessThanOrEqual(
            fitted.width,
            PaddrStyle.Metrics.minimumWindowSize.width + 0.5,
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
