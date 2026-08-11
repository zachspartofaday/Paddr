import SwiftUI

struct PermissionTile: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let isGranted: Bool
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? PaddrStyle.accent : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).paddrTypography(.callout).fontWeight(.semibold)
                Text(isGranted ? "Ready" : "Required")
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if !isGranted {
                Button("Request", action: requestAction)
                    .paddrActionButton(prominent: true)
                Button("Open Settings", systemImage: "gearshape", action: settingsAction)
                    .labelStyle(.iconOnly)
                    .paddrActionButton()
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.secondary.opacity(0.07), in: .rect(cornerRadius: 11))
        .help(Text(detail))
        .accessibilityElement(children: .contain)
    }
}
