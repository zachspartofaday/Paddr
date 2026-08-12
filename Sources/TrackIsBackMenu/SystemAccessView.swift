import PaddrAppSupport
import SwiftUI

struct SystemAccessView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                permissionsHeader
                Spacer(minLength: 8)
                HStack(spacing: 8) { permissionControls }
            }

            VStack(alignment: .leading, spacing: 8) {
                permissionsHeader
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { permissionControls }
                    VStack(spacing: 8) { permissionControls }
                }
            }
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }

    private var permissionsHeader: some View {
        Text("Permissions")
            .paddrTypography(.headline)
            .frame(minHeight: PaddrStyle.cardHeaderHeight)
            .fixedSize()
    }

    @ViewBuilder private var permissionControls: some View {
        PermissionTile(
            title: LocalizedStringResource("Accessibility"),
            detail: LocalizedStringResource("Reads trackpad reports and sends mapped mouse and keyboard input."),
            isGranted: model.accessibilityTrusted,
            requestAction: model.requestAccessibility,
            settingsAction: model.openAccessibilitySettings
        )
    }
}
