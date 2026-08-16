import AppKit
import SwiftUI

/// One row of the control state table. Every custom Paddr control resolves to exactly one
/// row, which supplies its fill, its stroke, and its label colour.
enum PaddrControlRow: Equatable {
    case rest
    case hover
    case pressed
    case selected
    case prominent
    case disabled
}

/// The inputs a custom control offers the state table, and the single place that resolves
/// them to one row.
///
/// Focus is deliberately not a row: the ring is drawn on top of whichever row won, so a
/// focused control never loses the state it was already showing.
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

    /// Disabled → Prominent → Selected → Pressed → Hover → Rest.
    var row: PaddrControlRow {
        if !isEnabled { return .disabled }
        if isProminent { return .prominent }
        if isSelected { return .selected }
        if isPressed { return .pressed }
        if isHovering { return .hover }
        return .rest
    }

    /// Additive on top of the winning row. A disabled control cannot take focus, so it
    /// never shows a ring.
    var showsFocusRing: Bool { isFocused && isEnabled }

    /// Prominent and Selected both outrank Pressed, so a prominent or selected control
    /// would otherwise report a press with no visible change at all. The pressed row's own
    /// fill value is applied additively there instead, which is what keeps the primary
    /// button's press feedback after `.borderedProminent` is replaced.
    var showsAdditivePressTint: Bool { isPressed && isEnabled && row != .pressed }

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
        case .rest, .hover, .pressed: AnyShapeStyle(.primary)
        case .selected: AnyShapeStyle(PaddrStyle.accentText)
        case .prominent: AnyShapeStyle(Color.white)
        case .disabled: AnyShapeStyle(.secondary)
        }
    }

    /// Fills are stated over `Color.primary` and `PaddrStyle.accent` so one set of values
    /// adapts to light and dark without a second palette. Disabled is the rest fill at 0.4.
    private var fillColor: Color {
        switch state.row {
        case .rest: Color.primary.opacity(0.06)
        case .hover: Color.primary.opacity(0.10)
        case .pressed: Color.primary.opacity(0.16)
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
            if state.showsAdditivePressTint {
                shape.fill(Color.primary.opacity(0.16))
            }
        }
    }

    private var strokeColor: Color? {
        switch state.row {
        case .rest, .hover, .pressed, .disabled: Color(nsColor: .separatorColor)
        case .selected: PaddrStyle.accent
        case .prominent: nil
        }
    }

    private var strokeOpacity: Double {
        switch state.row {
        case .rest: 0.50
        case .hover, .pressed: 0.70
        case .selected: 0.70
        case .disabled: 0.50 * 0.4
        case .prominent: 0
        }
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
                strokeColor.opacity(appearance.strokeOpacity(strokeOpacity)),
                lineWidth: max(strokeWidth, appearance.strokeWidth)
            )
        }
    }

    @ViewBuilder
    private var focusRing: some View {
        if state.showsFocusRing {
            shape.strokeBorder(PaddrStyle.accent, lineWidth: 2)
        }
    }
}

/// The button family. `primary` is the prominent row, `secondary` and `icon` start at rest,
/// and `icon` is square at `Metrics.control`.
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
                .padding(.horizontal, role == .icon ? 0 : PaddrStyle.Spacing.s2)
                .frame(
                    width: role == .icon ? PaddrStyle.Metrics.control : nil,
                    height: PaddrStyle.Metrics.control
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
