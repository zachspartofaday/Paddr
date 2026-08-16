import SwiftUI

struct PermissionTile: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let isGranted: Bool
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        HStack(spacing: PaddrStyle.Spacing.s2) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? PaddrStyle.accentSymbol : .orange)
                .accessibilityHidden(true)

            Text(title)
                .paddrTypography(.sectionLabel)

            Spacer(minLength: PaddrStyle.Spacing.s1)

            if !isGranted {
                Button("Request", action: requestAction)
                    .paddrActionButton(.primary)
                Button("Open Settings", systemImage: "gearshape", action: settingsAction)
                    .paddrActionButton(.icon)
            }
        }
        .padding(.horizontal, PaddrStyle.Spacing.s2)
        .frame(maxWidth: .infinity, minHeight: PaddrStyle.Metrics.row)
        .background(tileColor.opacity(0.07), in: .rect(cornerRadius: PaddrStyle.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: PaddrStyle.Radius.control)
                .strokeBorder(tileColor.opacity(0.20), lineWidth: 1)
        }
        .help(Text(detail))
        .accessibilityElement(children: .contain)
    }

    private var tileColor: Color { isGranted ? PaddrStyle.accent : .orange }
}
