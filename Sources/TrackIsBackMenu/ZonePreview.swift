import SwiftUI
import TrackIsBackCore

struct ZonePreview: View {
    let configuration: PadConfiguration

    var body: some View {
        Group {
            switch configuration.zoneLayout {
            case .radialFour:
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow { Color.clear; ZoneCell(binding: configuration.dpadKeys.up); Color.clear }
                    GridRow {
                        ZoneCell(binding: configuration.dpadKeys.left)
                        NeutralZoneCell()
                        ZoneCell(binding: configuration.dpadKeys.right)
                    }
                    GridRow { Color.clear; ZoneCell(binding: configuration.dpadKeys.down); Color.clear }
                }
            case .fourCorners:
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow { ZoneCell(binding: configuration.dpadKeys.up); ZoneCell(binding: configuration.dpadKeys.right) }
                    GridRow { ZoneCell(binding: configuration.dpadKeys.left); ZoneCell(binding: configuration.dpadKeys.down) }
                }
            case .horizontalTwo:
                HStack(spacing: 4) {
                    ZoneCell(binding: configuration.dpadKeys.left)
                    ZoneCell(binding: configuration.dpadKeys.right)
                }
            case .verticalTwo:
                VStack(spacing: 4) {
                    ZoneCell(binding: configuration.dpadKeys.up)
                    ZoneCell(binding: configuration.dpadKeys.down)
                }
            case .gridNine:
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        ZoneCell(binding: configuration.gridKeys.topLeft)
                        ZoneCell(binding: configuration.gridKeys.top)
                        ZoneCell(binding: configuration.gridKeys.topRight)
                    }
                    GridRow {
                        ZoneCell(binding: configuration.gridKeys.left)
                        ZoneCell(binding: configuration.gridKeys.center)
                        ZoneCell(binding: configuration.gridKeys.right)
                    }
                    GridRow {
                        ZoneCell(binding: configuration.gridKeys.bottomLeft)
                        ZoneCell(binding: configuration.gridKeys.bottom)
                        ZoneCell(binding: configuration.gridKeys.bottomRight)
                    }
                }
            }
        }
        .frame(height: 104)
        .padding(6)
        .background(.black.opacity(0.11))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.primary.opacity(0.08), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Button area preview")
    }
}
