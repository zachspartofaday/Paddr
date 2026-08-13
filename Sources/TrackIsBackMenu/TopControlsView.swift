import PaddrAppSupport
import SwiftUI

struct TopControlsView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ProfileControlsView(model: model)
                if !model.hasSystemAccess {
                    Spacer(minLength: 12)
                    permissionsContent
                }
            }
            .frame(minHeight: 40)

            VStack(alignment: .leading, spacing: 12) {
                ProfileControlsView(model: model)
                if !model.hasSystemAccess { permissionsContent }
            }
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }

    private var permissionsContent: some View {
        HStack(spacing: 12) {
            Text("Permissions")
                .paddrTypography(.headline)
                .frame(minHeight: PaddrStyle.cardHeaderHeight)
                .fixedSize()

            PermissionTile(
                title: LocalizedStringResource("Accessibility"),
                detail: LocalizedStringResource(
                    "Reads trackpad reports and sends mapped mouse and keyboard input."
                ),
                isGranted: model.accessibilityTrusted,
                requestAction: model.requestAccessibility,
                settingsAction: model.openAccessibilitySettings
            )
        }
        .frame(width: 470, alignment: .leading)
        .frame(minHeight: 40)
    }
}
