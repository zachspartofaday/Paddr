import PaddrAppSupport
import SwiftUI

struct TopControlsView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaddrStyle.Spacing.s3) {
                    ProfileControlsView(model: model)
                    Spacer(minLength: PaddrStyle.Spacing.s3)
                    saveState
                    actions
                }
                .frame(minHeight: PaddrStyle.Metrics.row)

                VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
                    ProfileControlsView(model: model)
                    HStack(spacing: PaddrStyle.Spacing.s3) {
                        saveState
                        Spacer(minLength: PaddrStyle.Spacing.s3)
                        actions
                    }
                }
            }
            if !model.hasSystemAccess { permissionsContent }
        }
        .padding(PaddrStyle.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }

    private var saveState: some View {
        Label(
            model.hasUnsavedChanges ? "Unsaved changes" : "Saved",
            systemImage: model.hasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill"
        )
        .paddrTypography(.rowLabel)
        .foregroundStyle(model.hasUnsavedChanges ? PaddrStyle.warningText : PaddrStyle.accentText)
        .fixedSize()
    }

    private var actions: some View {
        Button("Save & Apply", systemImage: "checkmark", action: model.saveAndApply)
            .paddrActionButton(.primary)
            .disabled(!model.canSaveAndApply)
            .keyboardShortcut("s", modifiers: .command)
    }

    private var permissionsContent: some View {
        HStack(spacing: PaddrStyle.Spacing.s3) {
            Text("Permissions")
                .paddrTypography(.sectionLabel)
                .fixedSize()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaddrStyle.Spacing.s2) {
                    inputMonitoringTile
                    accessibilityTile
                }
                VStack(spacing: PaddrStyle.Spacing.s2) {
                    inputMonitoringTile
                    accessibilityTile
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: PaddrStyle.Metrics.row)
    }

    private var inputMonitoringTile: some View {
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

    private var accessibilityTile: some View {
        PermissionTile(
            title: LocalizedStringResource("Accessibility"),
            detail: LocalizedStringResource(
                "Sends mapped mouse, scroll, and keyboard input."
            ),
            isGranted: model.accessibilityTrusted,
            requestAction: model.requestAccessibility,
            settingsAction: model.openAccessibilitySettings
        )
    }
}
