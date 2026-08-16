import SwiftUI

/// Static presentation shared by every on-screen representation of a physical
/// Steam Controller trackpad. Interactive overlays remain owned by their views.
struct CapacitivePadSurface: View {
    enum Layer: Equatable {
        case complete
        case fill
        case border
    }

    var layer: Layer = .complete

    var body: some View {
        ZStack {
            if layer != .border {
                Canvas { context, size in
                    let bounds = CGRect(origin: .zero, size: size)
                    let padShape = Path(
                        roundedRect: bounds,
                        cornerRadius: PaddrStyle.padPreviewCornerRadius
                    )
                    context.fill(
                        padShape,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.primary.opacity(0.085),
                                Color.primary.opacity(0.035)
                            ]),
                            startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                            endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
                        )
                    )
                }
                .clipShape(.rect(cornerRadius: PaddrStyle.padPreviewCornerRadius))
            }

            if layer != .fill {
                ZStack {
                    RoundedRectangle(cornerRadius: PaddrStyle.padPreviewCornerRadius)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        .padding(1)
                    RoundedRectangle(cornerRadius: PaddrStyle.padPreviewCornerRadius)
                        .strokeBorder(.primary.opacity(0.30), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
