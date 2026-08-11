import SwiftUI
import TrackIsBackCore

struct PadConfigurationView: View {
    let side: PadSide
    @Binding var configuration: PadConfiguration
    @State private var isExpanded = true

    private var title: LocalizedStringResource { side == .left ? "Left trackpad" : "Right trackpad" }
    private var sideSymbol: String { side == .left ? "l.circle.fill" : "r.circle.fill" }
    private var summary: LocalizedStringResource {
        switch configuration.mode {
        case .disabled: "Off"
        case .mouse: "Pointer"
        case .scroll: "Scroll"
        case .dpad: configuration.zoneLayout.displayName
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Behavior", selection: $configuration.mode) {
                    Text("Off").tag(PadMode.disabled)
                    Text("Pointer").tag(PadMode.mouse)
                    Text("Scroll").tag(PadMode.scroll)
                    Text("Zones").tag(PadMode.dpad)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Behavior")

                if configuration.mode == .mouse || configuration.mode == .scroll {
                    ValueSliderRow(
                        title: "Sensitivity",
                        systemImage: "speedometer",
                        value: $configuration.sensitivity,
                        range: ConfigurationLimits.sensitivity,
                        step: 0.1,
                        valueText: configuration.sensitivity.formatted(.number.precision(.fractionLength(1))) + "×"
                    )
                }

                if configuration.mode == .mouse {
                    ValueSliderRow(
                        title: "Center tap radius",
                        systemImage: "scope",
                        value: $configuration.mouseDeadzone,
                        range: ConfigurationLimits.mouseDeadzone,
                        step: 0.01,
                        valueText: configuration.mouseDeadzone.formatted(.percent.precision(.fractionLength(0)))
                    )
                    .help("The radius starts at the pad center. Movement pauses inside it, and leaving it cancels the tap.")
                }

                if configuration.mode.allowsTouchTap {
                    TapActionPicker(selection: $configuration.tapKey)
                }

                if configuration.mode == .dpad {
                    ButtonZoneConfigurationView(configuration: $configuration)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sideSymbol)
                    .paddrTypography(.headline)
                    .foregroundStyle(PaddrStyle.accent)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text(title).paddrTypography(.headline)
                Spacer()
                Text(summary)
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.10), in: .capsule)
            }
            .contentShape(.rect)
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
