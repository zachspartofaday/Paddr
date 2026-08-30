import PaddrAppSupport
import SwiftUI

struct TopControlsView: View {
    private static let reflowBreakpoint: CGFloat = 680

    @Bindable var model: PaddrMenuModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let usesInlineLayout = availableWidth > Self.reflowBreakpoint
        // Moving the same children keeps ProfileControlsView's prompt and confirmation state alive.
        let controlsLayout = usesInlineLayout
            ? AnyLayout(HStackLayout(alignment: .center, spacing: PaddrStyle.Spacing.s3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: PaddrStyle.Spacing.s3))

        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            controlsLayout {
                ProfileControlsView(model: model)

                HStack(spacing: PaddrStyle.Spacing.s3) {
                    saveState
                    if !usesInlineLayout {
                        Spacer(minLength: PaddrStyle.Spacing.s3)
                    }
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(minHeight: PaddrStyle.Metrics.row)
            if !model.hasSystemAccess { permissionsContent }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            guard width > 0 else { return }
            availableWidth = width
        }
    }

    private var saveState: some View {
        Label(
            model.hasUnsavedChanges ? "Unsaved changes" : "Saved",
            systemImage: model.hasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill"
        )
        .paddrTypography(.rowLabel)
        .foregroundStyle(model.hasUnsavedChanges ? PaddrStyle.warningText : PaddrStyle.accentText)
        .fixedSize()
        .accessibilityLabel(
            model.hasUnsavedChanges ? Text("Unsaved changes") : Text("Configuration saved")
        )
    }

    private var actions: some View {
        Button("Save & Apply", systemImage: "checkmark", action: model.saveAndApply)
            .paddrActionButton(.primary)
            .disabled(!model.canSaveAndApply)
            .keyboardShortcut("s", modifiers: .command)
            .paddrAccessibilityID("profile", "save-apply")
    }

    private var permissionsContent: some View {
        let usesColumns = availableWidth >= PaddrStyle.Metrics.permissionColumnsBreakpoint
            && !dynamicTypeSize.isAccessibilitySize
        let permissionsLayout = usesColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: PaddrStyle.Spacing.s3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: PaddrStyle.Spacing.s2))

        return VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s2) {
            PaddrSectionHeader("Permissions")
                .fixedSize()

            permissionsLayout {
                inputMonitoringTile
                accessibilityTile
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
            identifier: "input-monitoring",
            requestAccessibilityLabel: "Request Input Monitoring",
            settingsAccessibilityLabel: "Open Input Monitoring Settings",
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
            identifier: "accessibility",
            requestAccessibilityLabel: "Request Accessibility",
            settingsAccessibilityLabel: "Open Accessibility Settings",
            requestAction: model.requestAccessibility,
            settingsAction: model.openAccessibilitySettings
        )
    }
}
