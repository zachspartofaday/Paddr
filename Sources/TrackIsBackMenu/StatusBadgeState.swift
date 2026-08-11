import SwiftUI

enum StatusBadgeState {
    case ready
    case problem
    case neutral

    var color: Color {
        switch self {
        case .ready: TrackIsBackStyle.accent
        case .problem: .orange
        case .neutral: .secondary
        }
    }
}
