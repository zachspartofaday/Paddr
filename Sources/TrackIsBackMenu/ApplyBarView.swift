import PaddrAppSupport
import SwiftUI

struct ApplyBarView: View {
    @Bindable var model: PaddrMenuModel

    private var outputValue: LocalizedStringResource {
        if model.isRunning { return "Active" }
        if model.isEnabled { return "Waiting" }
        return "Idle"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                statusCells
                statusMessage
                    .frame(width: 230, height: 32, alignment: .leading)
                Spacer(minLength: 12)
                saveState
                actions
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) { statusCells }
                HStack(spacing: 12) {
                    statusMessage
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 32,
                            maxHeight: 32,
                            alignment: .leading
                        )
                    saveState
                    actions
                }
            }
        }
        .padding(.horizontal, PaddrStyle.panelPadding)
        .padding(.vertical, 8)
        .frame(minHeight: PaddrStyle.commandBarMinimumHeight)
        .background(.thickMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.42))
                .frame(height: 1)
        }
        .onChange(of: model.status) { _, status in
            guard status.messageState != nil else { return }
            AccessibilityNotification.Announcement(String(localized: status.message)).post()
        }
    }

    @ViewBuilder private var statusMessage: some View {
        if let messageState = model.status.messageState {
            Label {
                Text(model.status.message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(
                    systemName: messageState == .failure
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill"
                )
                .accessibilityHidden(true)
            }
            .paddrTypography(.caption)
            .foregroundStyle(
                messageState == .failure ? PaddrStyle.errorText : PaddrStyle.warningText
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.status.message)
            .help(Text(model.status.message))
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var statusCells: some View {
        StatusCell(
            title: LocalizedStringResource("Controller"),
            value: model.controllerConnected
                ? LocalizedStringResource("Connected")
                : LocalizedStringResource("Not found"),
            systemImage: model.controllerConnected ? "gamecontroller.fill" : "gamecontroller",
            state: model.controllerConnected ? .ready : .problem
        )
        StatusCell(
            title: LocalizedStringResource("Output"),
            value: outputValue,
            systemImage: model.isRunning
                ? "wave.3.right.circle.fill"
                : (model.isEnabled ? "hourglass.circle" : "pause.circle"),
            state: model.isRunning ? .active : .neutral
        )
        StatusCell(
            title: LocalizedStringResource("Access"),
            value: model.hasSystemAccess
                ? LocalizedStringResource("Ready")
                : LocalizedStringResource("Needed"),
            systemImage: model.hasSystemAccess ? "checkmark.shield.fill" : "exclamationmark.shield",
            state: model.hasSystemAccess ? .ready : .problem
        )
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
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button("Defaults", systemImage: "arrow.counterclockwise", action: model.restoreDefaults)
                    .paddrActionButton()
                    .disabled(!model.activeProfileControlsAppearEnabled)
                    .allowsHitTesting(model.canEditActiveProfile)
                    .accessibilityRespondsToUserInteraction(model.canEditActiveProfile)

                Button("Save & Apply", systemImage: "checkmark", action: model.saveAndApply)
                    .paddrActionButton(prominent: true)
                    .disabled(!model.canSaveAndApply)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}
