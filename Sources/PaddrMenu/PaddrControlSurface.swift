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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaddrStyle.Radius.control)
    }

    private var labelStyle: AnyShapeStyle {
        switch state.row {
        case .rest: AnyShapeStyle(.primary)
        case .selected: AnyShapeStyle(PaddrStyle.accentText)
        case .prominent: AnyShapeStyle(Color.white)
        case .disabled: AnyShapeStyle(.secondary)
        }
    }

    /// The base fill, before the interaction overlay. Stated over `Color.primary` and
    /// `PaddrStyle.accent` so one set of values adapts to light and dark without a second
    /// palette. Disabled is the rest fill at 0.4.
    var fillColor: Color {
        switch state.row {
        case .rest: Color.primary.opacity(0.06)
        case .selected: PaddrStyle.accent.opacity(0.18)
        case .prominent: PaddrStyle.accent
        case .disabled: Color.primary.opacity(0.06 * 0.4)
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

    private var strokeColor: Color? {
        switch state.row {
        case .rest, .disabled: Color(nsColor: .separatorColor)
        case .selected: PaddrStyle.accent
        case .prominent: nil
        }
    }

    /// The base stroke opacity, before the interaction overlay.
    private var strokeOpacity: Double {
        switch state.row {
        case .rest: 0.50
        case .selected: 0.70
        case .disabled: 0.50 * 0.4
        case .prominent: 0
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
    var focusRingColor: Color {
        state.row == .prominent ? Color.white : PaddrStyle.accent
    }

    @ViewBuilder
    private var focusRing: some View {
        if state.showsFocusRing {
            shape.strokeBorder(focusRingColor, lineWidth: 2)
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
                .paddrTypography(.rowLabel)
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
