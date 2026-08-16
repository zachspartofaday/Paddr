import SwiftUI

struct PanelBackgroundView: View {
    var body: some View {
        PaddrAppearanceReader { appearance in
            Group {
                if appearance.usesOpaqueFallback {
                    Rectangle().fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        LinearGradient(
                            colors: [
                                Color(nsColor: .windowBackgroundColor).opacity(0.72),
                                PaddrStyle.accent.opacity(0.055),
                                Color(nsColor: .windowBackgroundColor).opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
