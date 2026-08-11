import SwiftUI

struct StatusCell: View {
    let title: LocalizedStringResource
    let value: LocalizedStringResource
    let systemImage: String
    let state: StatusBadgeState

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
                    .foregroundStyle(state.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(.secondary.opacity(0.065), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
