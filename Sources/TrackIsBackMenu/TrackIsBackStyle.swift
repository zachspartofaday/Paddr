import AppKit
import SwiftUI

enum TrackIsBackStyle {
    static let accent = Color(red: 26.0 / 255.0, green: 159.0 / 255.0, blue: 1)
    static let panelWidth: CGFloat = 560
    static let preferredPanelHeight: CGFloat = 1_120
    static let panelPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 16

    @MainActor
    static func panelSize(for screen: NSScreen?) -> NSSize {
        let availableHeight = screen?.visibleFrame.height ?? preferredPanelHeight
        return NSSize(
            width: panelWidth,
            height: min(preferredPanelHeight, max(680, availableHeight - 40))
        )
    }
}
