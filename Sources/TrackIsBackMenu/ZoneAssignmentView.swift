import SwiftUI

struct ZoneAssignmentView: View {
    let title: LocalizedStringResource
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            OutputBindingPicker(selection: $selection, width: 126)
        }
    }
}
