import SwiftUI

struct StatusCell: View {
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    let systemImage: String
    let state: StatusBadgeState

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(state.color)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(title)
                .paddrTypography(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .paddrTypography(.callout)
                .bold()
                .foregroundStyle(state.textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(state.color.opacity(0.11), in: .capsule)
        .overlay {
            if colorSchemeContrast == .increased {
                Capsule().strokeBorder(state.color, lineWidth: 1.5)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
