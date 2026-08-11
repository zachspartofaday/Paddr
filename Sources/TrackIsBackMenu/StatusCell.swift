import SwiftUI

struct StatusCell: View {
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    let systemImage: String
    let state: StatusBadgeState

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(state.color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .paddrTypography(.callout)
                    .bold()
                    .foregroundStyle(state.textColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(state.color.opacity(0.09), in: .rect(cornerRadius: 10))
        .overlay {
            if colorSchemeContrast == .increased {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(state.color, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
