import SwiftUI

struct StatusBadge: View {
    let title: LocalizedStringResource
    let systemImage: String
    let state: StatusBadgeState

    var body: some View {
        Label(title, systemImage: systemImage)
            .paddrTypography(.caption)
            .lineLimit(1)
            .foregroundStyle(state.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(state.color.opacity(0.10), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(state.color.opacity(0.26), lineWidth: 1)
            }
    }
}
