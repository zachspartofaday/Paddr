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
                // Derived against the plate it sits on, not against the bare panel: the
                // plate is a wash of the same accent, and a wash pulls the background
                // toward the glyph.
                .foregroundStyle(isGranted ? PaddrAccentSurface.permissionTile.symbol : .orange)
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
        .background(
            PaddrAccentSurface.permissionTile.tint(tileColor),
            in: .rect(cornerRadius: PaddrStyle.Radius.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PaddrStyle.Radius.control)
                .strokeBorder(tileColor.opacity(0.20), lineWidth: 1)
        }
        .help(Text(detail))
        .accessibilityElement(children: .contain)
    }

    private var tileColor: Color { isGranted ? PaddrStyle.accent : .orange }
}
