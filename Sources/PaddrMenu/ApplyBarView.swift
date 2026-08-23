import PaddrAppSupport
import SwiftUI

struct ApplyBarView: View {
    @Bindable var model: PaddrMenuModel
    @State private var availableWidth: CGFloat = 0

    private var outputValue: LocalizedStringResource {
        if model.isRunning { return "Active" }
        if model.isReleasingOutput { return "Releasing" }
        if model.isEnabled { return "Waiting" }
        return "Idle"
    }

    private var batteryPresentation: BatteryStatusPresentation {
        BatteryStatusPresentation(status: model.batteryStatus)
    }

    var body: some View {
        let usesInlineLayout = availableWidth >= PaddrStyle.Metrics.defaultWindowSize.width
        let contentLayout = usesInlineLayout
            ? AnyLayout(HStackLayout(alignment: .center, spacing: PaddrStyle.Spacing.s1))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: PaddrStyle.Spacing.s1))

        contentLayout {
            HStack(spacing: PaddrStyle.Spacing.s1) {
                statusCells
            }
            .fixedSize(horizontal: true, vertical: false)

            statusMessage
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: PaddrStyle.Metrics.row,
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: PaddrStyle.Metrics.contentMaxWidth)
        .padding(.horizontal, PaddrStyle.Metrics.outerSpacing)
        .padding(.vertical, PaddrStyle.Spacing.s2)
        .frame(maxWidth: .infinity)
        .frame(minHeight: PaddrStyle.Metrics.commandBar)
        .background(PaddrStyle.night0.opacity(0.96))
        .overlay(alignment: .top) {
            PaddrAppearanceReader { appearance in
                Rectangle()
                    .fill(appearance.surfaceStroke)
                    .frame(height: appearance.strokeWidth)
            }
        }
        .paddrAccessibilityID("status-strip")
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            guard width > 0 else { return }
            availableWidth = width
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
            Label(
                model.readiness.nextAction.title,
                systemImage: model.readiness.nextAction.systemImage
            )
            .paddrTypography(.caption)
            .foregroundStyle(
                model.readiness.nextAction == .none
                    ? PaddrStyle.activeText
                    : PaddrStyle.textSecondary
            )
            .help(Text(model.readiness.nextAction.title))
            .paddrAccessibilityID("status", "next-action")
        }
    }

    @ViewBuilder private var statusCells: some View {
        StatusCell(
            title: LocalizedStringResource("Puck"),
            value: model.receiverDescription != nil
                ? LocalizedStringResource("Connected")
                : LocalizedStringResource("Not found"),
            systemImage: model.receiverDescription != nil
                ? "cable.connector"
                : "cable.connector.slash",
            state: model.receiverDescription != nil ? .ready : .problem,
            identifier: "puck"
        )
        StatusCell(
            title: LocalizedStringResource("Controller"),
            value: model.controllerConnected
                ? LocalizedStringResource("Connected")
                : LocalizedStringResource("Not found"),
            systemImage: model.controllerConnected ? "gamecontroller.fill" : "gamecontroller",
            state: model.controllerConnected ? .ready : .problem,
            identifier: "controller"
        )
        StatusCell(
            title: LocalizedStringResource("Battery"),
            value: batteryPresentation.compactValue,
            systemImage: batteryPresentation.systemImage,
            state: .neutral,
            accessibilityValue: batteryPresentation.accessibilityValue,
            identifier: "battery"
        )
        StatusCell(
            title: LocalizedStringResource("Output"),
            value: outputValue,
            systemImage: model.isRunning
                ? "wave.3.right.circle.fill"
                : (model.isEnabled ? "hourglass.circle" : "pause.circle"),
            state: model.isRunning ? .active : .neutral,
            identifier: "output"
        )
        StatusCell(
            title: LocalizedStringResource("Access"),
            value: model.hasSystemAccess
                ? LocalizedStringResource("Ready")
                : LocalizedStringResource("Needed"),
            systemImage: model.hasSystemAccess ? "checkmark.shield.fill" : "exclamationmark.shield",
            state: model.hasSystemAccess ? .ready : .problem,
            identifier: "access"
        )
    }

}
