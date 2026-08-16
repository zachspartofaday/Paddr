import AppKit
import SwiftUI

/// Static presentation shared by every on-screen representation of a physical
/// Steam Controller trackpad. Interactive overlays remain owned by their views.
struct CapacitivePadSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let electrodeInset: CGFloat = 7

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PaddrStyle.padPreviewCornerRadius)
                .fill(
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(reduceTransparency ? 1 : 0.66)
                )

            RoundedRectangle(cornerRadius: PaddrStyle.padPreviewCornerRadius)
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(
                        colorSchemeContrast == .increased ? 1 : 0.62
                    ),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )

            RoundedRectangle(
                cornerRadius: PaddrStyle.padPreviewCornerRadius - electrodeInset
            )
            .inset(by: electrodeInset)
            .strokeBorder(
                PaddrStyle.accent.opacity(
                    colorSchemeContrast == .increased ? 0.58 : 0.30
                ),
                lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
