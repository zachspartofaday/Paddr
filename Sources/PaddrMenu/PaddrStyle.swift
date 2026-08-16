import AppKit
import SwiftUI

/// The only vocabulary `PaddrMenu` text uses for a font. Every role carries its own
/// weight, so no call site follows `paddrTypography(_:)` with an ad-hoc `bold()`.
enum PaddrTextRole {
    /// Guide header.
    case pageTitle
    /// Pad-card and guide-page titles.
    case cardTitle
    /// Column and band headers.
    case sectionLabel
    /// Settings-row labels, normally paired with an SF Symbol.
    case rowLabel
    /// Action-button labels, for every `PaddrButtonRole`.
    ///
    /// Deliberately larger and heavier than ``rowLabel``, and the reason is a contrast
    /// threshold rather than a taste: the button's label is drawn on the accent fill, whose
    /// on-accent colour is derived at WCAG's 3.0:1 *large text* threshold. Large text is
    /// 18pt regular or 14pt bold, so at `.callout` — regular weight, 12pt — that threshold
    /// did not apply and 4.5:1 did. `.title3` is 15pt at the default size category, and this
    /// role carries `.bold`, which clears the 14pt-bold form of the threshold. It stays a
    /// system text style rather than a fixed point size so Dynamic Type still scales it, and
    /// scaling only ever moves it further above 14pt.
    case buttonLabel
    /// Status values and numeric readouts.
    case value
    /// Detail and secondary text.
    case caption

    var font: Font {
        switch self {
        case .pageTitle: .title2.bold()
        case .cardTitle: .headline
        case .sectionLabel: .subheadline.weight(.semibold)
        case .rowLabel: .callout
        case .buttonLabel: .title3.weight(.bold)
        case .value: .callout.monospacedDigit()
        case .caption: .caption
        }
    }
}

/// Emphasis of an action button. A band carries at most one `primary`.
enum PaddrButtonRole {
    case primary
    case secondary
    /// Icon-only; the role applies `labelStyle(.iconOnly)` so call sites do not repeat it.
    case icon
}

enum PaddrStyle {
    /// The one spacing scale. `s1` separates an icon from its label, `s2` two controls,
    /// `s3` two rows, `s4` two bands or a panel edge, `s5` the guide's bands.
    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 24
    }

    /// Heights and fixed surface sizes. `row` is the single control-row family
    /// (card header, settings row, status cell, permission row, inspector header), and
    /// `control` is the height every Paddr-drawn control is laid out at.
    enum Metrics {
        static let row: CGFloat = 28
        /// `row` plus a `Spacing.s2` inset above and below.
        static let commandBar: CGFloat = 44
        /// In-row custom controls, from LimitlessQuilter's dense
        /// `canvasToolbarControlHeight`. Sits inside `row` with room to centre.
        static let control: CGFloat = 24
        /// Action buttons, from LimitlessQuilter's standard `controlHeight`. Larger than the
        /// in-row height because no `paddrActionButton` call site sits inside a
        /// `PaddrSettingsRow` — every one is in a band or a footer, where a button taller
        /// than `row` costs the row rhythm nothing.
        static let button: CGFloat = 38
        /// Horizontal padding inside a Paddr-drawn control, from LimitlessQuilter's
        /// `controlHorizontalPadding`. Off the `Spacing` scale deliberately: it is a
        /// control's own geometry, paired with `button` and `control`, not a gap between two
        /// things.
        static let controlHorizontalPadding: CGFloat = 10

        static let defaultWindowSize = NSSize(width: 1_120, height: 600)
        static let minimumWindowSize = NSSize(width: 640, height: 360)
        static let guideWindowSize = NSSize(width: 680, height: 430)
        static let minimumGuideWindowSize = NSSize(width: 560, height: 430)

        static let zoneMapWidth: CGFloat = 190
        static let zoneMapHeight: CGFloat = 182
    }

    enum Radius {
        /// Card or banner, from LimitlessQuilter's `cardCornerRadius`.
        static let card: CGFloat = 14
        /// Paddr-drawn controls, and the inset containers that hold them, from
        /// LimitlessQuilter's `controlCornerRadius`.
        static let control: CGFloat = 7
        /// The physical trackpad. Geometry-bearing and unchanged.
        static let pad: CGFloat = 30
    }

    /// Widths are derived from the container they must fit, not chosen a priori. The binding
    /// constraint is the pad card's inspector column: a settings row's inline branch needs
    /// `labelColumn + Spacing.s3 + control <= zoneInspectorWidth`. Exceeding it does not clip
    /// — it silently drops every picker row into `PaddrSettingsRow`'s stacked fallback.
    enum Width {
        /// Numeric value column, monospaced and trailing-aligned.
        static let readout: CGFloat = 48
        /// Settings-row pickers.
        static let control: CGFloat = 132
        /// The area-layout picker, whose longest value is "Four-way radial".
        static let controlMedium: CGFloat = 160
        /// The profile picker, which sits in the full-width top band rather than a column.
        static let controlWide: CGFloat = 200
        /// Label column for rows whose control is a fixed-width picker.
        static let labelColumn: CGFloat = 108
        /// Label column for slider rows: their labels are longer ("Pointer acceleration")
        /// and their control is flexible, so they can afford what a picker row cannot.
        static let labelColumnWide: CGFloat = 152
    }

    /// The product accent is the viewer's macOS accent colour, not a fixed blue. Every
    /// accent-bearing surface in `PaddrMenu` reads it through this token, so a yellow,
    /// green, or graphite accent reaches all of them at once — and none of them may pair a
    /// hard-coded partner colour with it, because no fixed colour survives that range.
    static let accent = Color(nsColor: .controlAccentColor)

    /// The label drawn *on top of* an accent fill: black or white, whichever clears the
    /// 3.0:1 large-text threshold against the fill. The fixed white this replaced clears
    /// even that on only some of the eight accents macOS offers — 1.51:1 on yellow — and
    /// clears 4.5:1 on none of them, 3.52:1 on the stock blue included.
    ///
    /// The large-text threshold applies because ``PaddrTextRole/buttonLabel`` is 15pt bold,
    /// which is what every `PaddrButtonStyle` label is drawn at. That is the *only* thing
    /// licensing 3.0:1 here: while the button family used `.rowLabel` — `.callout`, regular
    /// weight, 12pt — this token was 4.5:1 text wearing a large-text justification, and
    /// white on the stock blue was a failure the derivation reported as a pass.
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        PaddrAccentPalette.onAccentLabel(
            for: PaddrAccentPalette.srgb(.controlAccentColor, in: appearance)
        )
    })

    /// The stroke drawn on top of an accent fill, derived so the rim as *drawn* — that is,
    /// composited at ``prominentStrokeOpacity`` — clears the 3:1 non-text ratio.
    static let onAccentStroke = Color(nsColor: NSColor(name: nil) { appearance in
        PaddrAccentPalette.onAccentStroke(
            for: PaddrAccentPalette.srgb(.controlAccentColor, in: appearance),
            drawnAt: prominentStrokeOpacity
        )
    })

    /// The prominent row's base stroke opacity. Below 1 on purpose: the interaction
    /// overlay's stroke term is additive, so a base at full opacity would clamp it away and
    /// leave hover on a primary button reading through fill alone.
    static let prominentStrokeOpacity: Double = 0.6

    static let active = Color(nsColor: .systemGreen)

    /// Green status text clears 4.5:1 in light appearance while retaining the
    /// brighter adaptive system green against dark backgrounds.
    static let activeText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemGreen
            : NSColor(srgbRed: 0, green: 0.42, blue: 0.18, alpha: 1)
    })

    /// Accent for text on the panel background. A raw accent does not generally clear 4.5:1
    /// against either background — the stock macOS blue reads 3.5:1 on the light one — and
    /// the accent is now the viewer's, so this cannot be a hand-tuned pair of blues. It is
    /// derived from whatever accent is selected, against the window background of the
    /// current appearance.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        PaddrAccentPalette.text(
            from: PaddrAccentPalette.srgb(.controlAccentColor, in: appearance),
            on: PaddrAccentPalette.srgb(.windowBackgroundColor, in: appearance)
        )
    })

    /// Accent for a meaning-bearing *symbol* on the panel background — the permission tile's
    /// granted checkmark, the status badge's ready glyph, and the increased-contrast badge
    /// outline drawn from the same token.
    ///
    /// A translucent accent *fill* may stay raw: it is decoration, and nothing is read from
    /// it. A symbol is not, and `accent` alone measures 1.51:1 against the light panel on the
    /// yellow accent — the exact ratio this palette already rejects for the label — with
    /// orange at 2.31:1 and green at 2.22:1 failing beside it. Non-text rather than text
    /// contrast because these are glyphs and boundaries, not prose; `accentText` remains the
    /// 4.5:1 token for the words next to them. The other five accents and all eight in dark
    /// appearance already clear 3.0:1, and the derivation returns those unchanged.
    static let accentSymbol = Color(nsColor: NSColor(name: nil) { appearance in
        PaddrAccentPalette.nonText(
            from: PaddrAccentPalette.srgb(.controlAccentColor, in: appearance),
            on: PaddrAccentPalette.srgb(.windowBackgroundColor, in: appearance)
        )
    })

    /// Warning text partner to `accentText`: system orange also fails contrast on
    /// light backgrounds, so light appearance darkens it.
    static let warningText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemOrange
            : NSColor(srgbRed: 0.65, green: 0.32, blue: 0, alpha: 1)
    })

    /// Error text follows the adaptive warning-token pattern instead of using the
    /// bright system red against light backgrounds.
    static let errorText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemRed
            : NSColor(srgbRed: 0.68, green: 0.08, blue: 0.08, alpha: 1)
    })

    // Sizes the token contract has not yet absorbed; slice 2 removes or rescales them.
    static let padColumnWidth: CGFloat = 530
    static let padConfigurationCardHeight: CGFloat = 420
    static let zoneInspectorWidth: CGFloat = 266
    static let behaviorPickerWidth: CGFloat = 272
    static let sliderMinimumWidth: CGFloat = 160
}

/// Turns an arbitrary accent colour into colours that meet WCAG contrast against the surface
/// they are drawn on.
///
/// This exists because the accent stopped being ours. `NSColor.controlAccentColor` is
/// whatever the viewer picked in System Settings — blue, purple, pink, red, orange, yellow,
/// green, or graphite — so no derived colour can be hand-tuned to a hue. Every entry point is
/// a *pure function of its input colours*, which is what lets the tests drive the real macOS
/// accent set through them instead of only the accent this machine happens to have set.
///
/// Derivation is always the *smallest* blend toward black or white that clears the target, so
/// a colour that already clears it is returned unchanged and the result stays as close to the
/// accent as the ratio allows.
enum PaddrAccentPalette {
    /// WCAG 2.1 AA for body text.
    static let textContrast: Double = 4.5
    /// WCAG 2.1 AA for a non-text boundary — a stroke or a component edge. Matches the
    /// ratios LimitlessQuilter documents.
    static let nonTextContrast: Double = 3.0

    /// The step of the blend search. 1% of the way to the endpoint is finer than any
    /// perceptible step and keeps the search exact enough to assert on.
    private static let step = 0.01

    /// Status and label text on the window background.
    ///
    /// The blend direction is chosen from the *background*, not the accent: on a light
    /// background every accent darkens, on a dark one every accent lightens. Both endpoints
    /// (black on light, white on dark) clear 4.5:1 by a wide margin, so the search always
    /// terminates on a colour that meets the target.
    static func text(from accent: NSColor, on background: NSColor) -> NSColor {
        derived(from: accent, on: background, clearing: textContrast)
    }

    /// A non-text accent on an arbitrary background — a focus ring, a component edge, or a
    /// meaning-bearing symbol. The same derivation as ``text(from:on:)`` at the boundary
    /// threshold rather than the body-text one, so there is one blend search, not two.
    static func nonText(from accent: NSColor, on background: NSColor) -> NSColor {
        derived(from: accent, on: background, clearing: nonTextContrast)
    }

    private static func derived(
        from accent: NSColor,
        on background: NSColor,
        clearing ratio: Double
    ) -> NSColor {
        smallestBlend(
            of: accent,
            toward: endpoint(on: background),
            clearing: ratio,
            against: background
        )
    }

    /// The endpoint every derivation blends toward: black on a light background, white on a
    /// dark one. Both clear either threshold by a wide margin, so a search toward this
    /// endpoint always terminates on a colour that meets its target.
    static func endpoint(on background: NSColor) -> NSColor {
        relativeLuminance(of: background) > equalContrastLuminance ? .black : .white
    }

    /// Source-over compositing of a translucent colour on an opaque one, which is what a
    /// tinted fill *is*: the same blend the derivations use, read in the other direction.
    static func composite(_ source: NSColor, over destination: NSColor, opacity: Double) -> NSColor {
        blend(destination, toward: source, amount: opacity)
    }

    /// The label drawn on top of an accent fill.
    ///
    /// White is used when it clears the 3.0:1 AA threshold for large text — which applies
    /// because ``PaddrTextRole/buttonLabel`` is 15pt bold, past the 14pt-bold form of
    /// WCAG's large-text definition, and not merely by assertion. White survives on
    /// saturated accents so buttons look native, and flips to black only where it is
    /// genuinely unreadable — 1.51:1 on the yellow accent `#FFCC00`.
    static func onAccentLabel(for accent: NSColor) -> NSColor {
        contrastRatio(.white, accent) >= nonTextContrast ? .white : .black
    }

    /// The stroke drawn on top of an accent fill, for a border drawn at `opacity`.
    ///
    /// The rim that has to clear 3:1 is the one on screen, and a partly transparent stroke
    /// over a solid fill *is* a blend of the two: drawing a colour blended `u` of the way to
    /// black at opacity `a` paints exactly the colour blended `u * a` of the way. So the
    /// search finds the blend the composite needs and divides it back out, rather than
    /// deriving a colour that only meets the ratio at an opacity the control never uses.
    static func onAccentStroke(for accent: NSColor, drawnAt opacity: Double) -> NSColor {
        // Darken by preference — a rim darker than its fill is the conventional bezel — and
        // lighten only for an accent too dark for black to separate from.
        let target: NSColor =
            contrastRatio(.black, accent) >= nonTextContrast ? .black : .white
        let composited = smallestBlendAmount(
            of: accent,
            toward: target,
            clearing: nonTextContrast,
            against: accent
        )
        let amount = min(1, composited / max(opacity, step))
        return blend(accent, toward: target, amount: amount)
    }

    /// Resolves a dynamic system colour — the accent and the window background both are —
    /// into concrete sRGB components under one appearance.
    static func srgb(_ color: NSColor, in appearance: NSAppearance) -> NSColor {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return resolved ?? color.usingColorSpace(.sRGB) ?? color
    }

    /// WCAG 2.1 relative luminance.
    static func relativeLuminance(of color: NSColor) -> Double {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    /// WCAG 2.1 contrast ratio, which is symmetric in its arguments.
    static func contrastRatio(_ one: NSColor, _ other: NSColor) -> Double {
        let a = relativeLuminance(of: one)
        let b = relativeLuminance(of: other)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The luminance at which black and white contrast equally — the crossover the
    /// black-or-white choice turns on.
    private static let equalContrastLuminance = sqrt(1.05 * 0.05) - 0.05

    private static func smallestBlend(
        of color: NSColor,
        toward target: NSColor,
        clearing ratio: Double,
        against background: NSColor
    ) -> NSColor {
        blend(
            color,
            toward: target,
            amount: smallestBlendAmount(
                of: color,
                toward: target,
                clearing: ratio,
                against: background
            )
        )
    }

    /// Contrast is monotone along a blend toward black or white, so the first amount that
    /// clears the target is the smallest one that does. A full blend that still falls short
    /// returns 1: the best the endpoint offers, never a colour below it.
    private static func smallestBlendAmount(
        of color: NSColor,
        toward target: NSColor,
        clearing ratio: Double,
        against background: NSColor
    ) -> Double {
        var amount = 0.0
        while amount < 1 {
            if contrastRatio(blend(color, toward: target, amount: amount), background) >= ratio {
                return amount
            }
            amount += step
        }
        return 1
    }

    /// A straight component blend in sRGB, which is the space the compositor draws these
    /// overlays in.
    private static func blend(_ color: NSColor, toward target: NSColor, amount: Double) -> NSColor {
        let from = color.usingColorSpace(.sRGB) ?? color
        let to = target.usingColorSpace(.sRGB) ?? target
        let fraction = CGFloat(min(max(amount, 0), 1))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + ((b - a) * fraction) }
        return NSColor(
            srgbRed: mix(from.redComponent, to.redComponent),
            green: mix(from.greenComponent, to.greenComponent),
            blue: mix(from.blueComponent, to.blueComponent),
            alpha: 1
        )
    }
}

private struct PaddrTypographyModifier: ViewModifier {
    let role: PaddrTextRole
    func body(content: Content) -> some View { content.font(role.font) }
}

private struct PaddrCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        PaddrAppearanceReader { appearance in
            // Bezeled, not glass. Paddr's controls are a mix of SwiftUI buttons, a SwiftUI
            // menu picker, and an AppKit `NSSegmentedControl`, and only the buttons can take
            // Liquid Glass — so a glass card sat above three controls that could never join
            // it. The standard control bezel is the one family all four share.
            Group {
                if appearance.usesOpaqueFallback {
                    content.background(
                        Color(nsColor: .controlBackgroundColor),
                        in: .rect(cornerRadius: PaddrStyle.Radius.card)
                    )
                } else {
                    content
                        .background(
                            PaddrStyle.accent.opacity(0.04),
                            in: .rect(cornerRadius: PaddrStyle.Radius.card)
                        )
                        .background(
                            .regularMaterial,
                            in: .rect(cornerRadius: PaddrStyle.Radius.card)
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: PaddrStyle.Radius.card)
                    .strokeBorder(
                        Color(nsColor: .separatorColor)
                            .opacity(appearance.strokeOpacity(0.46)),
                        lineWidth: appearance.strokeWidth
                    )
            }
        }
    }
}

private struct PaddrActionButtonModifier: ViewModifier {
    let role: PaddrButtonRole

    /// `focusEffectDisabled()` sits outside the `Button`, where the system effect is drawn;
    /// it suppresses the effect only, leaving the button in the keyboard focus order for
    /// `PaddrControlSurface` to draw the ring itself.
    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .primary, .secondary:
            content
                .buttonStyle(PaddrButtonStyle(role: role))
                .focusEffectDisabled()
        case .icon:
            content
                .labelStyle(.iconOnly)
                .buttonStyle(PaddrButtonStyle(role: .icon))
                .focusEffectDisabled()
        }
    }
}

extension View {
    func paddrTypography(_ role: PaddrTextRole) -> some View {
        modifier(PaddrTypographyModifier(role: role))
    }

    func paddrCard() -> some View { modifier(PaddrCardModifier()) }

    func paddrMenuSelector() -> some View {
        tint(Color(nsColor: .labelColor))
    }

    func paddrActionButton(_ role: PaddrButtonRole) -> some View {
        modifier(PaddrActionButtonModifier(role: role))
    }
}
