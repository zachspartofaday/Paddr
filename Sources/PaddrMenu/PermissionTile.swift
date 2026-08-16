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
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(tileColor.opacity(0.07), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tileColor.opacity(0.20), lineWidth: 1)
        }
        .help(Text(detail))
        .accessibilityElement(children: .contain)
    }

    private var tileColor: Color { isGranted ? PaddrStyle.accent : .orange }
}
