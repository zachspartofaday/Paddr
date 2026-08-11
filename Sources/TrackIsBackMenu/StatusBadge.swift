import SwiftUI

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let state: StatusBadgeState

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(state.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(state.color.opacity(0.12)), in: .capsule)
    }
}
