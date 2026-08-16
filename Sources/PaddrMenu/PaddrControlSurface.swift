import AppKit
import SwiftUI

/// The base appearance of a control: what the control *is*, before anything is done to it.
/// Role and selection only — interaction is deliberately not a row.
///
/// An earlier model gave hover and press rows of their own and ordered every input by
/// precedence. It produced the same defect twice: a prominent control showed no press, then
/// no hover, because Prominent outranked both, and Selected had the same hole waiting. Rows
/// that only interaction can occupy are what made that possible, so there are none.
enum PaddrControlRow: Equatable {
    case rest
    case selected
    case prominent
    case disabled
}

/// Interaction feedback, computed additively from the interaction flags and layered over
/// whichever base row the control resolved to.
///
/// There is no "the row already expresses this" exemption, because no row can: hover and
/// press are not rows. Both terms are *deltas* over the base — a hovered rest control fills
/// at `0.06 + 0.050`, and a hovered prominent one fills at solid accent plus `0.050`.
///
/// The values are LimitlessQuilter's action variant, restated here rather than imported:
/// `PaddrMenu` takes no cross-repository dependency.
struct PaddrInteractionOverlay: Equatable {
    /// Added to the base fill opacity, over `Color.primary`.
    var fillOpacity: Double = 0
    /// Added to the base stroke opacity.
    var strokeOpacity: Double = 0

    /// A control nothing is being done to, and every disabled control.
    static let none = PaddrInteractionOverlay()

    var isActive: Bool { self != .none }
}

/// The inputs a custom control offers the state table, and the single place that resolves
/// them into a base row plus the layers drawn over it.
///
/// Three of the six inputs never reach the row. Focus is drawn on top as a ring, and hover
/// and press are the additive ``interactionOverlay``. That is the whole rule: a row
/// expresses *what the control is*, and the additive layers express *what the pointer and
/// the keyboard are doing to it*, so the second can never be swallowed by the first.
struct PaddrControlState: Equatable {
    var isEnabled: Bool
    var isProminent: Bool
    var isSelected: Bool
    var isPressed: Bool
    var isHovering: Bool
    var isFocused: Bool

    init(
        isEnabled: Bool = true,
        isProminent: Bool = false,
        isSelected: Bool = false,
        isPressed: Bool = false,
        isHovering: Bool = false,
        isFocused: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.isProminent = isProminent
        self.isSelected = isSelected
        self.isPressed = isPressed
        self.isHovering = isHovering
        self.isFocused = isFocused
    }

    /// Disabled → Prominent → Selected → Rest. Only role and selection participate, so no
    /// ordering here can hide an interaction.
    var row: PaddrControlRow {
        if !isEnabled { return .disabled }
        if isProminent { return .prominent }
        if isSelected { return .selected }
        return .rest
    }

    /// Additive on top of the winning row. A disabled control cannot take focus, so it
    /// never shows a ring.
    var showsFocusRing: Bool { isFocused && isEnabled }

    /// The additive half of the state table, over *any* row. Hover and press share the base
    /// activation; a press deepens the fill on top of it, and selection deepens the stroke
    /// while the overlay is active. A disabled control zeroes every term: it never reacts.
    var interactionOverlay: PaddrInteractionOverlay {
        guard isEnabled, isPressed || isHovering else { return .none }
        return PaddrInteractionOverlay(
            fillOpacity: 0.050 + (isPressed ? 0.025 : 0),
            strokeOpacity: 0.36 + (isSelected ? 0.08 : 0)
        )
    }

    /// Selection is never colour-only: under Differentiate Without Colour a selected
    /// control also carries a leading checkmark. Tracks selection rather than the winning
    /// row, because a row that outranks Selected hides the selection colour entirely.
    func showsSelectionMark(in appearance: PaddrAppearance) -> Bool {
        appearance.usesShapeDifferentiation && isSelected && isEnabled
    }
}

/// Draws fill, stroke, and focus ring for a resolved ``PaddrControlState`` at
/// `Radius.control`. Sizing belongs to the control, not to the surface.
struct PaddrControlSurface: ViewModifier {
    let state: PaddrControlState

    func body(content: Content) -> some View {
        PaddrAppearanceReader { appearance in
            HStack(spacing: PaddrStyle.Spacing.s1) {
                if state.showsSelectionMark(in: appearance) {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                content
            }
            .foregroundStyle(labelStyle)
            .background { fill(appearance) }
            .overlay { border(appearance) }
            .overlay { focusRing }
            .animation(appearance.animation(.easeOut(duration: 0.12)), value: state)
        }
    }

    /// The control's outline. `.continuous` rather than the default `.circular`: it is the
    /// corner every other Paddr-drawn surface and the system's own controls use, and mixing
    /// the two families in one panel is visible as a mismatch long before either arc is.
    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaddrStyle.Radius.control, style: .continuous)
    }

    /// How far inside the control the focus ring is drawn. The ring used to share ``shape``
    /// with the border, so two antialiased strokes landed on one arc and the ring simply
    /// covered the border. On its own inset arc the two read as two.
    static let focusRingInset: CGFloat = 2

    /// The ring's arc: ``shape`` moved in by ``focusRingInset``, with the radius reduced to
    /// match so the inset stays constant around the curve rather than pinching at the corner.
    var focusRingShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: max(1, PaddrStyle.Radius.control - Self.focusRingInset),
            style: .continuous
        )
    }

    /// The label colour. The prominent row's label sits on solid accent, and the accent is
    /// the viewer's macOS accent — so the label is derived from the fill rather than fixed:
    /// white is unreadable on yellow, and misses 4.5:1 on the stock blue too.
    private var labelStyle: AnyShapeStyle {
        switch state.row {
        case .rest: AnyShapeStyle(.primary)
        case .selected: AnyShapeStyle(PaddrStyle.accentText)
        case .prominent: AnyShapeStyle(PaddrStyle.onAccent)
        case .disabled: AnyShapeStyle(.secondary)
        }
    }

    /// The base fill opacities. Named rather than written inline because the focus ring is
    /// derived against the fill it is drawn on: a second copy of these numbers in the ring's
    /// derivation is a copy that can drift, and a ring derived against a fill the control no
    /// longer draws clears nothing.
    static let restFillOpacity: Double = 0.06
    static let selectedFillOpacity: Double = 0.18
    static let disabledFillScale: Double = 0.4

    /// The base fill, before the interaction overlay. Stated over `Color.primary` and
    /// `PaddrStyle.accent` so one set of values adapts to light and dark without a second
    /// palette. Disabled is the rest fill at ``disabledFillScale``.
    var fillColor: Color {
        switch state.row {
        case .rest: Color.primary.opacity(Self.restFillOpacity)
        case .selected: PaddrStyle.accent.opacity(Self.selectedFillOpacity)
        case .prominent: PaddrStyle.accent
        case .disabled: Color.primary.opacity(Self.restFillOpacity * Self.disabledFillScale)
        }
    }

    @ViewBuilder
    private func fill(_ appearance: PaddrAppearance) -> some View {
        ZStack {
            // Reduce Transparency: an opaque control-background base under the same tint,
            // so the row stays distinguishable without a translucent fill.
            if appearance.usesOpaqueFallback {
                shape.fill(Color(nsColor: .controlBackgroundColor))
            }
            shape.fill(fillColor)
            // Drawn as its own layer rather than summed into `fillColor`: the prominent row
            // is solid accent, which no opacity addition can express.
            if state.interactionOverlay.isActive {
                shape.fill(Color.primary.opacity(state.interactionOverlay.fillOpacity))
            }
        }
    }

    /// Every row strokes. The prominent row's was `nil`, which made the interaction
    /// overlay's stroke term inert on exactly the row that needed it most — a primary button
    /// read hover and press through the fill delta alone. It cannot stroke in accent, for
    /// the same reason the focus ring cannot: its fill *is* the accent. It strokes in the
    /// derived on-accent rim instead.
    var strokeColor: Color? {
        switch state.row {
        case .rest, .disabled: Color(nsColor: .separatorColor)
        case .selected: PaddrStyle.accent
        case .prominent: PaddrStyle.onAccentStroke
        }
    }

    /// The base stroke opacity, before the interaction overlay.
    private var strokeOpacity: Double {
        switch state.row {
        case .rest: 0.50
        case .selected: 0.70
        case .disabled: 0.50 * 0.4
        case .prominent: PaddrStyle.prominentStrokeOpacity
        }
    }

    /// Base plus overlay, clamped: opacity has no meaning above 1, and a selected control
    /// pressed at full strength sums past it.
    var resolvedStrokeOpacity: Double {
        min(1, strokeOpacity + state.interactionOverlay.strokeOpacity)
    }

    /// Selected is the emphasis stroke at 1.5pt; increased contrast takes every stroke
    /// there, so the two never fight.
    private var strokeWidth: CGFloat {
        state.row == .selected ? 1.5 : 1
    }

    @ViewBuilder
    private func border(_ appearance: PaddrAppearance) -> some View {
        if let strokeColor {
            // Inset, not centred. A centred stroke was tried on the theory that it would cover
            // the fill's antialiased outer edge; measured at 1× it does the opposite. Under
            // `strokeBorder` the fringe pixels are already rim-coloured, so there is nothing
            // exposed to cover, and centring splits one full-strength rim pixel into two
            // half-strength ones: the prominent left edge went 0.431 to 0.714/0.714, and the
            // rest row's border faded to 0.075 against a 0.051 fill.
            shape.strokeBorder(
                strokeColor.opacity(appearance.strokeOpacity(resolvedStrokeOpacity)),
                lineWidth: max(strokeWidth, appearance.strokeWidth)
            )
        }
    }

    /// The ring is inset, not outset — the control sits in a `Metrics.row` band with about
    /// 2pt of clearance, so a halo drawn outside the shape would clip. An inset ring has to
    /// contrast with the fill it is drawn on top of, and the prominent row is solid accent:
    /// an accent ring there is the same colour as the button, which is no ring at all.
    ///
    /// A fixed white ring was the first repair and is no longer sufficient: once the accent
    /// became the viewer's, a white ring on a yellow accent is the same defect again, at
    /// 1.51:1. The prominent ring takes the same derived on-accent colour as the label.
    ///
    /// That repair reached one row and left three at the raw accent, which is the same
    /// defect with a paler fill underneath it: a yellow ring measures 1.32:1 on the rest
    /// row's near-white fill and 1.39:1 on the selected row's wash of that same yellow — and
    /// the ring is the *only* focus indication a Paddr control has. Every row now derives
    /// against its own fill at the 3.0:1 boundary threshold.
    var focusRingColor: Color {
        switch state.row {
        case .prominent: PaddrStyle.onAccent
        case .selected: Self.focusRingOnSelectedFill
        case .rest: Self.focusRingOnRestFill
        case .disabled: Self.focusRingOnDisabledFill
        }
    }

    /// The rest row's fill, resolved for one appearance.
    ///
    /// `Color.primary` is modelled as the appearance's plain black or white rather than
    /// `labelColor`'s 85% black: that makes the modelled fill darker than the drawn one in
    /// light appearance and lighter in dark, and in both directions that is the *harder*
    /// target for a ring derived against it. The backdrop is the window background, the
    /// same solid stand-in `PaddrStyle.accentText` resolves against — the card's real
    /// backing is `.regularMaterial`, which no solid colour is exactly.
    static func restFill(on background: NSColor, opacity: Double = restFillOpacity) -> NSColor {
        PaddrAccentPalette.composite(
            PaddrAccentPalette.endpoint(on: background),
            over: background,
            opacity: opacity
        )
    }

    /// The selected row's fill, resolved for one appearance. Exact rather than modelled:
    /// the tint is the accent itself.
    static func selectedFill(accent: NSColor, on background: NSColor) -> NSColor {
        PaddrAccentPalette.composite(accent, over: background, opacity: selectedFillOpacity)
    }

    /// The focus ring for one row, as a pure function of the accent and the background, so
    /// the tests can drive the whole macOS accent set through it rather than the single
    /// accent the test host happens to run with.
    static func focusRing(
        for row: PaddrControlRow,
        accent: NSColor,
        on background: NSColor
    ) -> NSColor {
        switch row {
        case .prominent:
            PaddrAccentPalette.onAccentLabel(for: accent)
        case .selected:
            PaddrAccentPalette.nonText(
                from: accent,
                on: selectedFill(accent: accent, on: background)
            )
        case .rest:
            PaddrAccentPalette.nonText(from: accent, on: restFill(on: background))
        case .disabled:
            PaddrAccentPalette.nonText(
                from: accent,
                on: restFill(on: background, opacity: restFillOpacity * disabledFillScale)
            )
        }
    }

    static let focusRingOnRestFill = focusRingToken(for: .rest)
    static let focusRingOnSelectedFill = focusRingToken(for: .selected)
    static let focusRingOnDisabledFill = focusRingToken(for: .disabled)

    private static func focusRingToken(for row: PaddrControlRow) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            focusRing(
                for: row,
                accent: PaddrAccentPalette.srgb(.controlAccentColor, in: appearance),
                on: PaddrAccentPalette.srgb(.windowBackgroundColor, in: appearance)
            )
        })
    }

    @ViewBuilder
    private var focusRing: some View {
        if state.showsFocusRing {
            focusRingShape
                .stroke(focusRingColor, lineWidth: 2)
                .padding(Self.focusRingInset)
        }
    }
}

/// The button family. `primary` is the prominent row, `secondary` and `icon` start at rest,
/// and `icon` is square at `Metrics.button`.
struct PaddrButtonStyle: ButtonStyle {
    let role: PaddrButtonRole

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(role: role, isPressed: configuration.isPressed, label: configuration.label)
    }

    /// A `ButtonStyle` is not a `View`, so enabled/focus/hover are read by a nested view
    /// that SwiftUI actually updates.
    private struct StyledLabel: View {
        let role: PaddrButtonRole
        let isPressed: Bool
        let label: ButtonStyleConfiguration.Label

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovering = false

        var body: some View {
            label
                // Every role, not only the prominent one: the button family shares one
                // label treatment, and the `onAccent` derivation's 3.0:1 large-text
                // threshold is licensed by this role being 15pt bold.
                .paddrTypography(.buttonLabel)
                .padding(
                    .horizontal,
                    role == .icon ? 0 : PaddrStyle.Metrics.controlHorizontalPadding
                )
                .frame(
                    width: role == .icon ? PaddrStyle.Metrics.button : nil,
                    height: PaddrStyle.Metrics.button
                )
                .paddrControlSurface(state)
                .contentShape(.rect(cornerRadius: PaddrStyle.Radius.control))
                .onHover { isHovering = $0 }
        }

        private var state: PaddrControlState {
            PaddrControlState(
                isEnabled: isEnabled,
                isProminent: role == .primary,
                isPressed: isPressed,
                isHovering: isHovering,
                isFocused: isFocused
            )
        }
    }
}

extension View {
    func paddrControlSurface(_ state: PaddrControlState) -> some View {
        modifier(PaddrControlSurface(state: state))
    }
}
