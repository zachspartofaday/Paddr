import SwiftUI
import PaddrCore

/// Non-interactive squircle preview shown for pointer, scroll, and off modes so every
/// pad card is anchored by the physical trackpad, matching the Zones area map.
/// Pointer mode mirrors runtime tap geometry: `PadMapper` treats the center tap
/// radius as a normalized Euclidean radius, which projects onto the pad as a
/// centered ellipse; taps register only inside it, or anywhere when the radius is 0.
struct PadModePreview: View {
    let mode: PadMode
    let deadzone: Double

    var body: some View {
        ZStack {
            CapacitivePadSurface()

            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                switch mode {
                case .mouse:
                    drawPointerOverlay(in: bounds, context: &context)
                case .scroll:
                    drawScrollChevrons(in: bounds, context: &context)
                case .disabled, .dpad:
                    break
                }
            }
            .clipShape(.rect(cornerRadius: PaddrStyle.padPreviewCornerRadius))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .opacity(mode == .disabled ? 0.45 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawPointerOverlay(in bounds: CGRect, context: inout GraphicsContext) {
        guard deadzone > 0 else {
            drawGlyph("cursorarrow.motionlines", in: bounds, context: &context)
            return
        }

        let tapRect = CGRect(
            x: bounds.midX - bounds.width * deadzone / 2,
            y: bounds.midY - bounds.height * deadzone / 2,
            width: bounds.width * deadzone,
            height: bounds.height * deadzone
        )
        let tapArea = Path(ellipseIn: tapRect)
        context.fill(tapArea, with: .color(PaddrStyle.accent.opacity(0.18)))
        context.stroke(
            tapArea,
            with: .color(PaddrStyle.accent.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
        )
        if min(tapRect.width, tapRect.height) >= 26 {
            drawGlyph("hand.tap", in: bounds, context: &context)
        }
    }

    private func drawScrollChevrons(in bounds: CGRect, context: inout GraphicsContext) {
        let inset: CGFloat = 22
        let arm: CGFloat = 7
        let chevrons: [(tip: CGPoint, dx: CGFloat, dy: CGFloat)] = [
            (CGPoint(x: bounds.midX, y: bounds.minY + inset), 1, 1),
            (CGPoint(x: bounds.midX, y: bounds.maxY - inset), 1, -1),
            (CGPoint(x: bounds.minX + inset, y: bounds.midY), 1, 0),
            (CGPoint(x: bounds.maxX - inset, y: bounds.midY), -1, 0)
        ]
        for chevron in chevrons {
            var path = Path()
            if chevron.dy == 0 {
                path.move(to: CGPoint(x: chevron.tip.x + arm * chevron.dx, y: chevron.tip.y - arm))
                path.addLine(to: chevron.tip)
                path.addLine(to: CGPoint(x: chevron.tip.x + arm * chevron.dx, y: chevron.tip.y + arm))
            } else {
                path.move(to: CGPoint(x: chevron.tip.x - arm, y: chevron.tip.y + arm * chevron.dy))
                path.addLine(to: chevron.tip)
                path.addLine(to: CGPoint(x: chevron.tip.x + arm, y: chevron.tip.y + arm * chevron.dy))
            }
            context.stroke(
                path,
                with: .color(.secondary.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawGlyph(_ systemImage: String, in bounds: CGRect, context: inout GraphicsContext) {
        context.draw(
            Text(Image(systemName: systemImage))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary.opacity(0.75)),
            at: CGPoint(x: bounds.midX, y: bounds.midY)
        )
    }
}
