import SwiftUI

struct PermissionTile: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(isGranted ? TrackIsBackStyle.accent : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isGranted {
                Label("Ready", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Request", action: requestAction)
                            .buttonStyle(.glass)

                        Button("Open Settings", systemImage: "gearshape", action: settingsAction)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .help("Open \(title) settings")
                    }
                    .controlSize(.regular)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.primary.opacity(0.045))
        .clipShape(.rect(cornerRadius: 10))
    }
}
