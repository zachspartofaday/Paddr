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

            Text(title)
                .paddrTypography(.callout)
                .bold()

            Spacer(minLength: 4)

            if !isGranted {
                Button("Request", action: requestAction)
                    .paddrActionButton(prominent: true)
                Button("Open Settings", systemImage: "gearshape", action: settingsAction)
                    .labelStyle(.iconOnly)
                    .paddrActionButton()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(.secondary.opacity(0.045), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.38), lineWidth: 1)
        }
        .help(Text(detail))
        .accessibilityElement(children: .contain)
    }
}
