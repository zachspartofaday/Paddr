import SwiftUI

struct PanelBackgroundView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.72),
                    TrackIsBackStyle.accent.opacity(0.055),
                    Color(nsColor: .windowBackgroundColor).opacity(0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
