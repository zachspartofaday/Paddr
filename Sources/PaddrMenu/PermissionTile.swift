import SwiftUI

struct PermissionTile: View {
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let isGranted: Bool
    var identifier: String = "permission"
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        PaddrAppearanceReader { appearance in
            tile(appearance: appearance)
        }
    }

    private func tile(appearance: PaddrAppearance) -> some View {
        HStack(spacing: PaddrStyle.Spacing.s2) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? PaddrStyle.activeText : PaddrStyle.warningText)
                .accessibilityHidden(true)

            Text(title)
                .paddrTypography(.sectionLabel)

            if isGranted {
                Text("Ready")
                    .paddrTypography(.caption)
                    .foregroundStyle(PaddrStyle.activeText)
            } else {
                Text("Needed")
                    .paddrTypography(.caption)
                    .foregroundStyle(PaddrStyle.warningText)
            }

            Spacer(minLength: PaddrStyle.Spacing.s1)

            if !isGranted {
                Button("Request", action: requestAction)
                    .paddrActionButton(.primary)
                    .paddrAccessibilityID("permissions", identifier, "request")
                Button("Open Settings", systemImage: "gearshape", action: settingsAction)
                    .paddrActionButton(.icon)
                    .paddrAccessibilityID("permissions", identifier, "settings")
            }
        }
        .padding(.horizontal, PaddrStyle.Spacing.s2)
        .frame(maxWidth: .infinity, minHeight: PaddrStyle.Metrics.row)
        .background(
            tileColor.opacity(PaddrStyle.permissionFillOpacity),
            in: .rect(cornerRadius: PaddrStyle.Radius.control)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PaddrStyle.Radius.control)
                .strokeBorder(
                    tileColor.opacity(
                        appearance.strokeOpacity(PaddrStyle.permissionStrokeOpacity)
                    ),
                    lineWidth: appearance.strokeWidth
                )
        }
        .help(Text(detail))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(isGranted ? Text("Ready") : Text("Needed"))
        .paddrAccessibilityID("permissions", identifier)
    }

    private var tileColor: Color { isGranted ? PaddrStyle.successGreen : PaddrStyle.cautionAmber }
}
