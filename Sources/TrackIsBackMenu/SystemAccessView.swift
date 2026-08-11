import PaddrAppSupport
import SwiftUI

struct SystemAccessView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System access needed", systemImage: "lock.shield")
                .paddrTypography(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { permissionControls }
                VStack(spacing: 8) { permissionControls }
            }
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }

    @ViewBuilder private var permissionControls: some View {
        PermissionTile(
            title: LocalizedStringResource("Input Monitoring"),
            detail: LocalizedStringResource("Reads controller trackpad reports."),
            isGranted: model.inputMonitoringStatus == .granted,
            requestAction: model.requestInputMonitoring,
            settingsAction: model.openInputMonitoringSettings
        )
        PermissionTile(
            title: LocalizedStringResource("Accessibility"),
            detail: LocalizedStringResource("Sends mapped mouse and keyboard input."),
            isGranted: model.accessibilityTrusted,
            requestAction: model.requestAccessibility,
            settingsAction: model.openAccessibilitySettings
        )
    }
}
