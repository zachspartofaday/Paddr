import AppKit
import PaddrAppSupport
import SwiftUI

struct AppHeaderView: View {
    @Bindable var model: PaddrMenuModel

    private var outputTitle: LocalizedStringResource {
        if model.isRunning { return "Output active" }
        if model.isEnabled { return "Output waiting" }
        return "Output idle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Trackpad Configuration")
                    .paddrTypography(.title)

                Spacer()

                Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshStatus)
                    .labelStyle(.iconOnly)
                    .paddrActionButton()
                    .help("Refresh controller and permission status")

                Toggle("Trackpad output", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityValue(
                        model.isEnabled
                            ? LocalizedStringResource("On")
                            : LocalizedStringResource("Off")
                    )
            }

            statusStrip

            if model.status.needsActionMessage {
                Label {
                    Text(model.status.message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: statusMessageSymbol)
                        .accessibilityHidden(true)
                }
                .paddrTypography(.caption)
                .foregroundStyle(statusMessageColor)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }

    private var statusStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { statusPills }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    controllerPill
                    outputPill
                }
                GridRow { accessPill }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var statusPills: some View {
        controllerPill
        outputPill
        accessPill
    }

    private var controllerPill: some View {
        StatusBadge(
            title: model.controllerConnected ? "Controller connected" : "Controller not found",
            systemImage: model.controllerConnected ? "gamecontroller.fill" : "gamecontroller",
            state: model.controllerConnected ? .ready : .problem
        )
    }

    private var outputPill: some View {
        StatusBadge(
            title: outputTitle,
            systemImage: model.isRunning ? "wave.3.right.circle.fill" : (model.isEnabled ? "hourglass.circle" : "pause.circle"),
            state: model.isRunning ? .ready : .neutral
        )
    }

    private var accessPill: some View {
        StatusBadge(
            title: model.hasSystemAccess ? "Access ready" : "Access needed",
            systemImage: model.hasSystemAccess ? "checkmark.shield.fill" : "exclamationmark.shield",
            state: model.hasSystemAccess ? .ready : .problem
        )
    }

    private var statusMessageSymbol: String {
        if case .failure = model.status { return "exclamationmark.triangle.fill" }
        return model.status == .configurationSaved ? "checkmark.circle.fill" : "info.circle.fill"
    }

    private var statusMessageColor: Color {
        if case .failure = model.status { return .red }
        return .secondary
    }
}
