import SwiftUI

struct SystemAccessView: View {
    @Bindable var model: TrackIsBackMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System access", systemImage: "lock.shield")
                .font(.headline)

            VStack(spacing: 8) {
                PermissionTile(
                    title: "Input Monitoring",
                    detail: "Allows PuckPads to read controller trackpad reports.",
                    isGranted: model.inputMonitoringStatus == "granted",
                    requestAction: model.requestInputMonitoring,
                    settingsAction: model.openInputMonitoringSettings
                )
                PermissionTile(
                    title: "Accessibility",
                    detail: "Allows mapped mouse and keyboard events in other apps.",
                    isGranted: model.accessibilityTrusted,
                    requestAction: model.requestAccessibility,
                    settingsAction: model.openAccessibilitySettings
                )
            }
        }
        .padding(TrackIsBackStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: TrackIsBackStyle.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: TrackIsBackStyle.cardCornerRadius)
                .stroke(.primary.opacity(0.07), lineWidth: 0.75)
        }
    }
}
