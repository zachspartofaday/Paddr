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
                Spacer(minLength: 12)
                saveState
                actions
            }
            .frame(minHeight: 40)

            VStack(alignment: .leading, spacing: 12) {
                ProfileControlsView(model: model)
                if !model.hasSystemAccess { permissionsContent }
                HStack(spacing: 12) {
                    saveState
                    Spacer(minLength: 12)
                    actions
                }
            }
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }

    private var saveState: some View {
        Label(
            model.hasUnsavedChanges ? "Unsaved changes" : "Saved",
            systemImage: model.hasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill"
        )
        .paddrTypography(.callout)
        .foregroundStyle(model.hasUnsavedChanges ? PaddrStyle.warningText : PaddrStyle.accentText)
        .fixedSize()
    }

    private var actions: some View {
        Button("Save & Apply", systemImage: "checkmark", action: model.saveAndApply)
            .paddrActionButton(prominent: true)
            .disabled(!model.canSaveAndApply)
            .keyboardShortcut("s", modifiers: .command)
    }

    private var permissionsContent: some View {
        HStack(spacing: 12) {
            Text("Permissions")
                .paddrTypography(.headline)
                .frame(minHeight: PaddrStyle.cardHeaderHeight)
                .fixedSize()

            VStack(spacing: 8) {
                PermissionTile(
                    title: LocalizedStringResource("Accessibility"),
                    detail: LocalizedStringResource(
                        "Sends mapped mouse, scroll, and keyboard input."
                    ),
                    isGranted: model.accessibilityTrusted,
                    requestAction: model.requestAccessibility,
                    settingsAction: model.openAccessibilitySettings
                )

                PermissionTile(
                    title: LocalizedStringResource("Input Monitoring"),
                    detail: LocalizedStringResource(
                        "Receives Steam Controller 2 reports from the puck."
                    ),
                    isGranted: model.inputMonitoringGranted,
                    requestAction: model.requestInputMonitoring,
                    settingsAction: model.openInputMonitoringSettings
                )
            }
        }
        .frame(width: 470, alignment: .leading)
        .frame(minHeight: 40)
    }
}
