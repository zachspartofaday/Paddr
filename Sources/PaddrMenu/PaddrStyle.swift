import AppKit
import SwiftUI

/// The only vocabulary `PaddrMenu` text uses for a font. Every role carries its own
/// weight, so no call site follows `paddrTypography(_:)` with an ad-hoc `bold()`.
enum PaddrTextRole {
    /// Guide header.
    case pageTitle
    /// Pad-card and guide-page titles.
    case cardTitle
    /// Titles for preview and settings regions within a card.
    case sectionTitle
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
        case .sectionTitle: .headline
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
    /// (card header, settings row, status cell, permission row, inspector header);
    /// control heights themselves stay native and are never hand-set.
    enum Metrics {
        static let controlHeight: CGFloat = 38
        static let row = controlHeight
        /// `row` plus a `Spacing.s2` inset above and below.
        static let commandBar: CGFloat = 54

        static let outerSpacing: CGFloat = 24
        /// Fresh windows match the approved side-by-side preview-and-settings composition.
        /// Restored and user-sized windows remain fluid around this default.
        static let defaultWindowSize = NSSize(width: 1_280, height: 700)
        static let defaultContentWidth = defaultWindowSize.width - (2 * outerSpacing)
        /// Below this content width, two complete pad editors no longer have
        /// enough room for their native mode controls and stack vertically.
        static let padEditorColumnsBreakpoint: CGFloat = 760
        /// The status row has its own content budget for enlarged, padded pills and guidance.
        static let statusBarInlineBreakpoint: CGFloat = 1_120
        static let minimumWindowSize = NSSize(width: 680, height: 520)
        static let guideWindowSize = NSSize(width: 720, height: 480)
        static let minimumGuideWindowSize = NSSize(width: 640, height: 460)

        static let zoneMapWidth: CGFloat = 190
        static let zoneMapHeight: CGFloat = 182
    }

    enum Radius {
        /// Console card or banner.
        static let card: CGFloat = 12
        /// Inset controls, status containers, and zone label plates.
        static let control: CGFloat = 7
        /// The physical trackpad. Geometry-bearing and unchanged.
        static let pad: CGFloat = 30
    }

    /// Widths are derived from the container they must fit, not chosen a priori. The binding
    /// constraint is the inset section inside one default dual-pad column: a settings row's
    /// inline branch must fit after both the card and section padding are removed.
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
        /// Label column for slider rows. It is wide enough for "Pointer acceleration"
        /// while preserving a usable native slider at the dual-column breakpoint.
        static let labelColumnWide: CGFloat = 136
    }

    // Family-console palette adapted under the bounded MIT grant recorded in
    // docs/ui/PADDR_FAMILY_UI_PARITY.md. Product-specific source names are intentionally
    // replaced with Paddr-local neutral vocabulary.
    static let night0 = Color(red: 5.0 / 255.0, green: 6.0 / 255.0, blue: 13.0 / 255.0)
    static let night1 = Color(red: 13.0 / 255.0, green: 17.0 / 255.0, blue: 38.0 / 255.0)
    static let interfaceBlue = Color(red: 51.0 / 255.0, green: 158.0 / 255.0, blue: 1)
    static let interfacePurple = Color(red: 115.0 / 255.0, green: 89.0 / 255.0, blue: 1)
    static let successGreen = Color(red: 70.0 / 255.0, green: 180.0 / 255.0, blue: 135.0 / 255.0)
    static let cautionAmber = Color(red: 1, green: 179.0 / 255.0, blue: 64.0 / 255.0)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 215.0 / 255.0, green: 233.0 / 255.0, blue: 1)
    static let textTertiary = Color(red: 157.0 / 255.0, green: 196.0 / 255.0, blue: 248.0 / 255.0)
    static let errorText = Color(red: 1, green: 0.36, blue: 0.36)

    static let accent = interfaceBlue
    static let active = successGreen
    static let activeText = successText
    static let accentText = interfaceBlue
    static let warningText = cautionAmber
    static let accentGradient = LinearGradient(
        colors: [interfaceBlue, interfacePurple],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let surface = Color.white.opacity(0.05)
    static let elevatedSurface = Color.white.opacity(0.08)
    static let surfaceStroke = Color.white.opacity(0.10)

    // Semantic derivatives preserve the canonical family palette above while pairing
    // colors for the contrast requirements of the UI element that renders them.
    // `interfaceBlue` remains the accent for text and artwork; native prominent and
    // selected controls need a darker tint because AppKit renders their labels white.
    static let controlTint = Color(
        red: 0,
        green: 110.0 / 255.0,
        blue: 195.0 / 255.0
    )
    static let controlForeground = textPrimary
    static let successText = Color(
        red: 82.0 / 255.0,
        green: 201.0 / 255.0,
        blue: 154.0 / 255.0
    )
    static let selectedZoneFillTop = interfaceBlue.opacity(0.42)
    static let selectedZoneFillBottom = interfacePurple.opacity(0.24)
    static let selectedTapFill = interfacePurple.opacity(0.24)
    static let selectionBoundary = textPrimary
    static let selectedZoneCaptionFill = controlTint
    static let selectedZoneCaptionForeground = controlForeground
    static let permissionFillOpacity = 0.07
    static let permissionStrokeOpacity = 0.75

    static let padColumnWidth = (Metrics.defaultContentWidth - Spacing.s3) / 2
    static let minimumPadColumnWidth = (
        Metrics.padEditorColumnsBreakpoint - Spacing.s3
    ) / 2
    static let minimumPadSectionWidth = minimumPadColumnWidth - (4 * Spacing.s3)
    static let previewInspectorSpacing = Spacing.s5
    static let previewInspectorColumnsBreakpoint = Metrics.zoneMapWidth
        + minimumPadSectionWidth
        + previewInspectorSpacing
    static let behaviorPickerWidth: CGFloat = 272
    static let sliderMinimumWidth = minimumPadSectionWidth
        - Width.labelColumnWide
        - Spacing.s3
        - Spacing.s2
        - Width.readout
}

private struct PaddrTypographyModifier: ViewModifier {
    let role: PaddrTextRole
    func body(content: Content) -> some View { content.font(role.font) }
}

private struct PaddrCardModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        PaddrAppearanceReader { appearance in
            content
                .background(
                    appearance.usesOpaqueFallback
                        ? PaddrStyle.night1
                        : appearance.surface(elevated: true),
                    in: .rect(cornerRadius: PaddrStyle.Radius.card)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PaddrStyle.Radius.card)
                        .strokeBorder(
                            appearance.surfaceStroke,
                            lineWidth: appearance.strokeWidth
                        )
                }
        }
    }
}

private struct PaddrActionButtonModifier: ViewModifier {
    let role: PaddrButtonRole

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .primary:
            content
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .paddrTypography(.rowLabel)
                .foregroundStyle(PaddrStyle.controlForeground)
                .tint(PaddrStyle.controlTint)
                .frame(minHeight: PaddrStyle.Metrics.controlHeight)
        case .secondary:
            content
                .buttonStyle(.bordered)
                .controlSize(.large)
                .paddrTypography(.rowLabel)
                .frame(minHeight: PaddrStyle.Metrics.controlHeight)
        case .icon:
            content
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .paddrTypography(.rowLabel)
                .frame(minHeight: PaddrStyle.Metrics.controlHeight)
        }
    }
}

extension View {
    func paddrTypography(_ role: PaddrTextRole) -> some View {
        modifier(PaddrTypographyModifier(role: role))
    }

    func paddrCard() -> some View { modifier(PaddrCardModifier()) }

    func paddrMenuSelector() -> some View {
        controlSize(.large)
            .frame(minHeight: PaddrStyle.Metrics.controlHeight)
            .tint(PaddrStyle.textPrimary)
    }

    func paddrActionButton(_ role: PaddrButtonRole) -> some View {
        modifier(PaddrActionButtonModifier(role: role))
    }
}
