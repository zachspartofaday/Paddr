import SwiftUI

struct KeyAssignmentGrid: View {
    let entries: [KeyAssignment]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
            ForEach(entries) { entry in
                GridRow {
                    Text(entry.title)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 86, alignment: .leading)
                    OutputBindingPicker(selection: entry.selection)
                }
            }
        }
    }
}
