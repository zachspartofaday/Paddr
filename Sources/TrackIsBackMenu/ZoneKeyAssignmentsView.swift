import SwiftUI
import TrackIsBackCore

struct ZoneKeyAssignmentsView: View {
    @Binding var configuration: PadConfiguration

    var body: some View {
        switch configuration.zoneLayout {
        case .radialFour:
            KeyAssignmentGrid(entries: [
                KeyAssignment(id: "up", title: "Up", selection: $configuration.dpadKeys.up),
                KeyAssignment(id: "right", title: "Right", selection: $configuration.dpadKeys.right),
                KeyAssignment(id: "down", title: "Down", selection: $configuration.dpadKeys.down),
                KeyAssignment(id: "left", title: "Left", selection: $configuration.dpadKeys.left)
            ])
        case .fourCorners:
            KeyAssignmentGrid(entries: [
                KeyAssignment(id: "top-left", title: "Top left", selection: $configuration.dpadKeys.up),
                KeyAssignment(id: "top-right", title: "Top right", selection: $configuration.dpadKeys.right),
                KeyAssignment(id: "bottom-right", title: "Bottom right", selection: $configuration.dpadKeys.down),
                KeyAssignment(id: "bottom-left", title: "Bottom left", selection: $configuration.dpadKeys.left)
            ])
        case .horizontalTwo:
            KeyAssignmentGrid(entries: [
                KeyAssignment(id: "left-half", title: "Left half", selection: $configuration.dpadKeys.left),
                KeyAssignment(id: "right-half", title: "Right half", selection: $configuration.dpadKeys.right)
            ])
        case .verticalTwo:
            KeyAssignmentGrid(entries: [
                KeyAssignment(id: "top-half", title: "Top half", selection: $configuration.dpadKeys.up),
                KeyAssignment(id: "bottom-half", title: "Bottom half", selection: $configuration.dpadKeys.down)
            ])
        case .gridNine:
            Grid(horizontalSpacing: 8, verticalSpacing: 9) {
                GridRow {
                    ZoneAssignmentView(title: "Top left", selection: $configuration.gridKeys.topLeft)
                    ZoneAssignmentView(title: "Top", selection: $configuration.gridKeys.top)
                    ZoneAssignmentView(title: "Top right", selection: $configuration.gridKeys.topRight)
                }
                GridRow {
                    ZoneAssignmentView(title: "Left", selection: $configuration.gridKeys.left)
                    ZoneAssignmentView(title: "Center", selection: $configuration.gridKeys.center)
                    ZoneAssignmentView(title: "Right", selection: $configuration.gridKeys.right)
                }
                GridRow {
                    ZoneAssignmentView(title: "Bottom left", selection: $configuration.gridKeys.bottomLeft)
                    ZoneAssignmentView(title: "Bottom", selection: $configuration.gridKeys.bottom)
                    ZoneAssignmentView(title: "Bottom right", selection: $configuration.gridKeys.bottomRight)
                }
            }
        }
    }
}
