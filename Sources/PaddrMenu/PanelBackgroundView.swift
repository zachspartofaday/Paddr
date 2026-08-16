import SwiftUI

struct PanelBackgroundView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Rectangle().fill(Color(nsColor: .windowBackgroundColor))
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
