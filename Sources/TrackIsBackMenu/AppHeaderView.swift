import AppKit
import SwiftUI

struct AppHeaderView: View {
    @Bindable var model: TrackIsBackMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PuckPads")
                        .font(.title2.bold())
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Toggle(isOn: $model.isEnabled) {
                    Text(model.isEnabled ? "On" : "Off")
                        .font(.headline)
                }
                .toggleStyle(.switch)
                .controlSize(.regular)
                .accessibilityLabel("Trackpad output")
                .accessibilityValue(model.isEnabled ? "On" : "Off")
            }

            HStack(spacing: 8) {
                StatusBadge(
                    title: model.controllerConnected ? "Controller connected" : "Controller not found",
                    systemImage: model.controllerConnected ? "gamecontroller.fill" : "gamecontroller",
                    state: model.controllerConnected ? .ready : .problem
                )
                StatusBadge(
                    title: model.isRunning ? "Output active" : "Output idle",
                    systemImage: model.isRunning ? "wave.3.right.circle.fill" : "pause.circle",
                    state: model.isRunning ? .ready : .neutral
                )
            }

            if model.isRunning {
                Text("\(model.reportCount) reports · \(model.actionCount) mapped actions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(TrackIsBackStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: TrackIsBackStyle.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: TrackIsBackStyle.cardCornerRadius)
                .stroke(.primary.opacity(0.08), lineWidth: 0.75)
        }
    }
}
