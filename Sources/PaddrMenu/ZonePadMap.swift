import PaddrAppSupport
import SwiftUI
import PaddrCore

struct ZonePadMap: View {
    let layout: PadZoneLayout
    let deadzone: Double
    let configuration: PadConfiguration
    @Binding var selection: ButtonZone
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                let padShape = Path(roundedRect: bounds, cornerRadius: PaddrStyle.padPreviewCornerRadius)
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

                for zone in layout.zones {
                    let path = path(for: zone, in: bounds)
                    let isSelected = zone == selection
                    context.fill(
                        path,
                        with: isSelected
                            ? .linearGradient(
                                Gradient(colors: [
                                    PaddrStyle.accent.opacity(0.34),
                                    PaddrStyle.accent.opacity(0.18)
                                ]),
                                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
                            )
                            : .color(.primary.opacity(0.025))
                    )
                    context.stroke(
                        path,
                        with: .color(isSelected ? PaddrStyle.accent.opacity(0.95) : .primary.opacity(0.19)),
                        lineWidth: isSelected ? 1.75 : 0.75
                    )
                    drawLabel(for: zone, selected: isSelected, in: bounds, context: &context)
                }

                if let neutral = neutralPath(in: bounds) {
                    context.fill(neutral, with: .color(.black.opacity(0.16)))
                    context.stroke(
                        neutral,
                        with: .color(.secondary.opacity(0.62)),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    context.draw(
                        Text(verbatim: "○")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary),
                        at: center(in: bounds)
                    )
                }
            }
            .clipShape(.rect(cornerRadius: PaddrStyle.padPreviewCornerRadius))
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: PaddrStyle.padPreviewCornerRadius)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                        .padding(1)
                    RoundedRectangle(cornerRadius: PaddrStyle.padPreviewCornerRadius)
                        .strokeBorder(
                            .primary.opacity(0.30),
                            lineWidth: 1
                        )
                }
            }
            .contentShape(.interaction, .rect(cornerRadius: PaddrStyle.padPreviewCornerRadius))
            .contentShape(.focusEffect, .rect(cornerRadius: PaddrStyle.padPreviewCornerRadius))
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if let zone = hitZone(at: value.location, size: proxy.size) {
                        selection = zone
                    }
                }
            )
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let direction: ZoneNavigationDirection
            switch press.key {
            case .leftArrow: direction = .left
            case .rightArrow: direction = .right
            case .upArrow: direction = .up
            case .downArrow: direction = .down
            default: return .ignored
            }
            selection = ZoneSelectionPolicy.moved(from: selection, direction: direction, in: layout)
            return .handled
        }
        .accessibilityHidden(true)
        .help("Select a highlighted pad area, then choose its keyboard or mouse action.")
    }

    private func hitZone(at point: CGPoint, size: CGSize) -> ButtonZone? {
        guard size.width > 0, size.height > 0 else { return nil }
        let x = ((point.x / size.width) * 2 - 1).clamped(to: -1...1)
        let y = (1 - (point.y / size.height) * 2).clamped(to: -1...1)
        let rawX = Int16((x * Double(Int16.max)).rounded())
        let rawY = Int16((y * Double(Int16.max)).rounded())
        return PadMapper.activeButtonZones(x: rawX, y: rawY, deadzone: deadzone, layout: layout).first
    }

    private func path(for zone: ButtonZone, in bounds: CGRect) -> Path {
        let midX = bounds.midX
        let midY = bounds.midY
        switch layout {
        case .radialFour:
            switch zone {
            case .up: return polygon([CGPoint(x: midX, y: midY), bounds.origin, CGPoint(x: bounds.maxX, y: bounds.minY)])
            case .right: return polygon([CGPoint(x: midX, y: midY), CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY)])
            case .down: return polygon([CGPoint(x: midX, y: midY), CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)])
            default: return polygon([CGPoint(x: midX, y: midY), CGPoint(x: bounds.minX, y: bounds.maxY), bounds.origin])
            }
        case .fourCorners:
            switch zone {
            case .topLeft: return Path(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height / 2))
            case .topRight: return Path(CGRect(x: midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height / 2))
            case .bottomRight: return Path(CGRect(x: midX, y: midY, width: bounds.width / 2, height: bounds.height / 2))
            default: return Path(CGRect(x: bounds.minX, y: midY, width: bounds.width / 2, height: bounds.height / 2))
            }
        case .horizontalTwo:
            return Path(CGRect(x: zone == .left ? bounds.minX : midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height))
        case .verticalTwo:
            return Path(CGRect(x: bounds.minX, y: zone == .up ? bounds.minY : midY, width: bounds.width, height: bounds.height / 2))
        case .gridNine:
            let index = layout.zones.firstIndex(of: zone) ?? 0
            let column = index % 3
            let row = index / 3
            return Path(CGRect(
                x: bounds.minX + CGFloat(column) * bounds.width / 3,
                y: bounds.minY + CGFloat(row) * bounds.height / 3,
                width: bounds.width / 3,
                height: bounds.height / 3
            ))
        }
    }

    private func neutralPath(in bounds: CGRect) -> Path? {
        guard let rect = ZoneMapGeometry.neutralRect(
            in: bounds,
            deadzone: deadzone,
            layout: layout
        ) else { return nil }
        switch layout {
        case .horizontalTwo:
            return Path(rect)
        case .verticalTwo:
            return Path(rect)
        case .radialFour, .fourCorners:
            return Path(ellipseIn: rect)
        case .gridNine:
            return nil
        }
    }

    private func labelPoint(for zone: ButtonZone, in bounds: CGRect) -> CGPoint {
        let position: CGPoint
        switch layout {
        case .radialFour:
            position = switch zone {
            case .up: CGPoint(x: 0.5, y: 0.23)
            case .right: CGPoint(x: 0.77, y: 0.5)
            case .down: CGPoint(x: 0.5, y: 0.77)
            default: CGPoint(x: 0.23, y: 0.5)
            }
        case .fourCorners:
            position = switch zone {
            case .topLeft: CGPoint(x: 0.25, y: 0.25)
            case .topRight: CGPoint(x: 0.75, y: 0.25)
            case .bottomRight: CGPoint(x: 0.75, y: 0.75)
            default: CGPoint(x: 0.25, y: 0.75)
            }
        case .horizontalTwo:
            position = CGPoint(x: zone == .left ? 0.25 : 0.75, y: 0.5)
        case .verticalTwo:
            position = CGPoint(x: 0.5, y: zone == .up ? 0.25 : 0.75)
        case .gridNine:
            let columns: [ButtonZone: CGFloat] = [
                .topLeft: 1.0 / 6.0, .left: 1.0 / 6.0, .bottomLeft: 1.0 / 6.0,
                .up: 0.5, .center: 0.5, .down: 0.5,
                .topRight: 5.0 / 6.0, .right: 5.0 / 6.0, .bottomRight: 5.0 / 6.0
            ]
            let rows: [ButtonZone: CGFloat] = [
                .topLeft: 1.0 / 6.0, .up: 1.0 / 6.0, .topRight: 1.0 / 6.0,
                .left: 0.5, .center: 0.5, .right: 0.5,
                .bottomLeft: 5.0 / 6.0, .down: 5.0 / 6.0, .bottomRight: 5.0 / 6.0
            ]
            position = CGPoint(x: columns[zone] ?? 0.5, y: rows[zone] ?? 0.5)
        }
        return CGPoint(
            x: bounds.minX + bounds.width * position.x,
            y: bounds.minY + bounds.height * position.y
        )
    }

    private func drawLabel(
        for zone: ButtonZone,
        selected: Bool,
        in bounds: CGRect,
        context: inout GraphicsContext
    ) {
        let point = labelPoint(for: zone, in: bounds)
        let plateSize = CGSize(width: layout == .gridNine ? 38 : 78, height: 22)
        let plateRect = CGRect(
            x: point.x - plateSize.width / 2,
            y: point.y - plateSize.height / 2,
            width: plateSize.width,
            height: plateSize.height
        )
        let plate = Path(roundedRect: plateRect, cornerRadius: plateSize.height / 2)
        if selected {
            context.fill(plate, with: .color(PaddrStyle.accentText.opacity(0.92)))
            context.stroke(plate, with: .color(.white.opacity(0.42)), lineWidth: 0.75)
        } else {
            context.fill(plate, with: .color(.primary.opacity(0.10)))
            context.stroke(plate, with: .color(.primary.opacity(0.14)), lineWidth: 0.75)
        }
        context.draw(
            OutputBindingText.text(for: configuration[bindingFor: zone])
                .font(.caption2.weight(.semibold))
                .foregroundStyle(selected ? .white : .secondary),
            at: point
        )
    }

    private func center(in bounds: CGRect) -> CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
