import SwiftUI

struct PermissionTile: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let isGranted: Bool
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? PaddrStyle.accentText : PaddrStyle.warningText)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .paddrTypography(.callout)
                    .bold()
                Text(detail)
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !isGranted {
                Button("Request", action: requestAction)
                    .paddrActionButton(prominent: true)
                Button("Open Settings", systemImage: "gearshape", action: settingsAction)
                    .labelStyle(.iconOnly)
                    .paddrActionButton()
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .help(Text(detail))
        .accessibilityElement(children: .contain)
        .accessibilityValue(isGranted ? Text("Ready") : Text("Needed"))
    }
}
