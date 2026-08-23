import SwiftUI

enum StatusBadgeState {
    case active
    case ready
    case problem
    case critical
    case neutral

    /// Icon and background-tint color.
    var color: Color {
        switch self {
        case .active: PaddrStyle.active
        case .ready: PaddrStyle.successGreen
        case .problem: PaddrStyle.cautionAmber
        case .critical: PaddrStyle.errorText
        case .neutral: PaddrStyle.textTertiary
        }
    }

    /// Text color: appearance-adaptive so status values keep contrast in light mode.
    var textColor: Color {
        switch self {
        case .active: PaddrStyle.activeText
        case .ready: PaddrStyle.activeText
        case .problem: PaddrStyle.warningText
        case .critical: PaddrStyle.errorText
        case .neutral: PaddrStyle.textTertiary
        }
    }
}
