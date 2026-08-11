import PaddrAppSupport
import SwiftUI

struct AppHeaderView: View {
    @Bindable var model: PaddrMenuModel

    private var outputValue: LocalizedStringResource {
        if model.isRunning { return "Active" }
        if model.isEnabled { return "Waiting" }
        return "Idle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    statusTitle
                    statusStrip
                }

                VStack(alignment: .leading, spacing: 8) {
                    statusTitle
                    statusStrip
                }
            }

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
            HStack(spacing: 8) {
                statusCells
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    controllerCell
                    outputCell
                }
                GridRow { accessCell }
            }
            VStack(spacing: 8) { statusCells }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var statusTitle: some View {
        Text("Status")
            .paddrTypography(.headline)
            .frame(minWidth: 72, alignment: .leading)
    }

    @ViewBuilder private var statusCells: some View {
        controllerCell
        outputCell
        accessCell
    }

    private var controllerCell: some View {
        StatusCell(
            title: "Controller",
            value: model.controllerConnected ? "Connected" : "Not found",
            systemImage: model.controllerConnected ? "gamecontroller.fill" : "gamecontroller",
            state: model.controllerConnected ? .ready : .problem
        )
    }

    private var outputCell: some View {
        StatusCell(
            title: "Output",
            value: outputValue,
            systemImage: model.isRunning ? "wave.3.right.circle.fill" : (model.isEnabled ? "hourglass.circle" : "pause.circle"),
            state: model.isRunning ? .ready : .neutral
        )
    }

    private var accessCell: some View {
        StatusCell(
            title: "Access",
            value: model.hasSystemAccess ? "Ready" : "Needed",
            systemImage: model.hasSystemAccess ? "checkmark.shield.fill" : "exclamationmark.shield",
            state: model.hasSystemAccess ? .ready : .problem
        )
    }

    private var statusMessageSymbol: String {
        if case .failure = model.status { return "exclamationmark.triangle.fill" }
        return "info.circle.fill"
    }

    private var statusMessageColor: Color {
        if case .failure = model.status { return .red }
        return .secondary
    }
}
