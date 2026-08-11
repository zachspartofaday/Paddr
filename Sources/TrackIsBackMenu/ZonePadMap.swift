import PaddrAppSupport
import SwiftUI
import TrackIsBackCore

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
                context.fill(Path(bounds), with: .color(.secondary.opacity(0.08)))

                for zone in layout.zones {
                    let path = path(for: zone, in: bounds)
                    context.fill(
                        path,
                        with: .color(zone == selection ? PaddrStyle.accent.opacity(0.38) : .primary.opacity(0.055))
                    )
                    context.stroke(
                        path,
                        with: .color(zone == selection ? PaddrStyle.accent : .primary.opacity(0.22)),
                        lineWidth: zone == selection ? 1.5 : 1
                    )
                    context.draw(
                        OutputBindingText.text(for: configuration[bindingFor: zone])
                            .font(.caption.bold())
                            .foregroundStyle(zone == selection ? .primary : .secondary),
                        at: labelPoint(for: zone, in: bounds)
                    )
                }

                if let neutral = neutralPath(in: bounds) {
                    context.fill(neutral, with: .color(.secondary.opacity(0.16)))
                    context.stroke(neutral, with: .color(.secondary.opacity(0.32)), lineWidth: 1)
                    context.draw(Text("Neutral").font(.caption).foregroundStyle(.secondary), at: center(in: bounds))
                }
            }
            .clipShape(.rect(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(
                        isFocused ? PaddrStyle.accent : .primary.opacity(0.24),
                        lineWidth: isFocused ? 3 : 1
                    )
            }
            .contentShape(.rect)
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
        let columns: [ButtonZone: CGFloat] = [.topLeft: 0.17, .left: 0.17, .bottomLeft: 0.17, .up: 0.5, .center: 0.5, .down: 0.5, .topRight: 0.83, .right: 0.83, .bottomRight: 0.83]
        let rows: [ButtonZone: CGFloat] = [.topLeft: 0.17, .up: 0.17, .topRight: 0.17, .left: 0.5, .center: 0.5, .right: 0.5, .bottomLeft: 0.83, .down: 0.83, .bottomRight: 0.83]
        return CGPoint(x: bounds.minX + bounds.width * (columns[zone] ?? 0.5), y: bounds.minY + bounds.height * (rows[zone] ?? 0.5))
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
