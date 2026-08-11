import SwiftUI
import TrackIsBackCore

struct PadConfigurationView: View {
    let side: PadSide
    @Binding var configuration: PadConfiguration
    @State private var isExpanded = true

    private var title: String { side == .left ? "Left trackpad" : "Right trackpad" }
    private var sideSymbol: String { side == .left ? "l.circle.fill" : "r.circle.fill" }
    private var summary: String {
        configuration.mode == .dpad
            ? configuration.zoneLayout.displayName
            : configuration.mode.rawValue.capitalized
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Behavior", selection: $configuration.mode) {
                    Text("Off").tag(PadMode.disabled)
                    Text("Pointer").tag(PadMode.mouse)
                    Text("Scroll").tag(PadMode.scroll)
                    Text("Zones").tag(PadMode.dpad)
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)

                if configuration.mode == .mouse || configuration.mode == .scroll {
                    ValueSliderRow(
                        title: "Sensitivity",
                        systemImage: "speedometer",
                        value: $configuration.sensitivity,
                        range: 0.1...20,
                        step: 0.1,
                        valueText: configuration.sensitivity.formatted(.number.precision(.fractionLength(1))) + "×"
                    )
                }

                if configuration.mode == .mouse {
                    ValueSliderRow(
                        title: "Center tap radius",
                        systemImage: "scope",
                        value: $configuration.mouseDeadzone,
                        range: 0...1,
                        step: 0.01,
                        valueText: configuration.mouseDeadzone.formatted(.percent.precision(.fractionLength(0)))
                    )

                    Label(
                        "The percentage is the radius from the pad center. Movement pauses inside it; leaving cancels the tap.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TapActionPicker(selection: $configuration.tapKey)

                if configuration.mode == .dpad {
                    ButtonZoneConfigurationView(configuration: $configuration)
                }
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sideSymbol)
                    .font(.title3)
                    .foregroundStyle(TrackIsBackStyle.accent)
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.headline)

                Spacer()

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
            .contentShape(.rect)
        }
        .padding(TrackIsBackStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: TrackIsBackStyle.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: TrackIsBackStyle.cardCornerRadius)
                .stroke(.primary.opacity(0.08), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
