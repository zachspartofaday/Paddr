import SwiftUI

enum StatusBadgeState {
    case active
    case ready
    case problem
    case neutral

    /// The wash behind the badge. Decoration, so it stays the raw colour — and the *raw*
    /// one rather than ``color`` on purpose: the icon and the value are derived against
    /// this wash, and a wash taken from them in turn would have no fixed point.
    private var tintBase: Color {
        switch self {
        case .active: PaddrStyle.active
        case .ready: PaddrStyle.accent
        case .problem: .orange
        case .neutral: .secondary
        }
    }

    /// The wash as ``StatusCell`` draws it.
    var tint: Color { PaddrAccentSurface.statusBadge.tint(tintBase) }

    /// Icon colour, and the increased-contrast capsule outline drawn from the same token.
    /// Both sit on ``tint`` rather than on the bare panel background, so the accent case
    /// derives against the capsule's own surface.
    var color: Color {
        switch self {
        case .active: PaddrStyle.active
        case .ready: PaddrAccentSurface.statusBadge.symbol
        case .problem: .orange
        case .neutral: .secondary
        }
    }

    /// Text color: appearance-adaptive so status values keep contrast in light mode, and on
    /// the accent case derived against ``tint`` for the same reason ``color`` is.
    var textColor: Color {
        switch self {
        case .active: PaddrStyle.activeText
        case .ready: PaddrAccentSurface.statusBadge.text
        case .problem: PaddrStyle.warningText
        case .neutral: .secondary
        }
    }
}
