import SwiftUI

struct PanelBackgroundView: View {
    var body: some View {
        PaddrAppearanceReader { appearance in
            LinearGradient(
                colors: appearance.hasIncreasedContrast
                    ? [Color.black, PaddrStyle.night0]
                    : [PaddrStyle.night1, PaddrStyle.night0],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
