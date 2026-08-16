import SwiftUI

enum StatusBadgeState {
    case active
    case ready
    case problem
    case neutral

    /// Icon and background-tint color.
    var color: Color {
        switch self {
        case .active: PaddrStyle.active
        case .ready: PaddrStyle.accentSymbol
        case .problem: .orange
        case .neutral: .secondary
        }
    }

    /// Text color: appearance-adaptive so status values keep contrast in light mode.
    var textColor: Color {
        switch self {
        case .active: PaddrStyle.activeText
        case .ready: PaddrStyle.accentText
        case .problem: PaddrStyle.warningText
        case .neutral: .secondary
        }
    }
}
