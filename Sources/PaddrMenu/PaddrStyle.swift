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

    static let accent = Color(red: 26.0 / 255.0, green: 159.0 / 255.0, blue: 1)
    static let active = Color(nsColor: .systemGreen)

    /// Green status text clears 4.5:1 in light appearance while retaining the
    /// brighter adaptive system green against dark backgrounds.
    static let activeText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemGreen
            : NSColor(srgbRed: 0, green: 0.42, blue: 0.18, alpha: 1)
    })

    /// Accent for text: the bright product accent reads at only ~2.8:1 against light
    /// backgrounds, so light appearance gets a darker variant that clears 4.5:1.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 26.0 / 255.0, green: 159.0 / 255.0, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0, green: 0.42, blue: 0.75, alpha: 1)
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
