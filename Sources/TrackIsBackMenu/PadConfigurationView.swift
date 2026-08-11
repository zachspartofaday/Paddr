import SwiftUI
import TrackIsBackCore

struct PadConfigurationView: View {
    let side: PadSide
    @Binding var configuration: PadConfiguration
    @State private var isExpanded = true

    private var title: LocalizedStringResource { side == .left ? "Left trackpad" : "Right trackpad" }
    private var summary: LocalizedStringResource {
        switch configuration.mode {
        case .disabled: "Off"
        case .mouse: "Pointer"
        case .scroll: "Scroll"
        case .dpad: configuration.zoneLayout.displayName
        }
    }

    private var settingsTitle: LocalizedStringResource {
        switch configuration.mode {
        case .disabled: "Trackpad off"
        case .mouse: "Pointer settings"
        case .scroll: "Scroll settings"
        case .dpad: "Zone settings"
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: PaddrStyle.settingsRowSpacing) {
                HStack(spacing: 12) {
                    Picker("Behavior", selection: $configuration.mode) {
                        Text("Off").tag(PadMode.disabled)
                        Text("Pointer").tag(PadMode.mouse)
                        Text("Scroll").tag(PadMode.scroll)
                        Text("Zones").tag(PadMode.dpad)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 8)

                    if configuration.mode == .dpad {
                        Picker("Area layout", selection: $configuration.zoneLayout) {
                            ForEach(PadZoneLayout.allCases, id: \.self) { layout in
                                Text(layout.displayName).tag(layout)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160, alignment: .trailing)
                        .help("Choose how the trackpad is divided into button areas.")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: PaddrStyle.behaviorRowHeight)
                .padding(.horizontal, PaddrStyle.insetHorizontalPadding)

                PaddrSectionContainer(title: settingsTitle) {
                    modeSettings
                }
            }
            .padding(.top, PaddrStyle.settingsRowSpacing)
        } label: {
            HStack(spacing: 10) {
                Text(title).paddrTypography(.headline)
                Spacer()
                Text(summary)
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.10), in: .capsule)
            }
            .frame(minHeight: PaddrStyle.cardHeaderHeight)
            .contentShape(.rect)
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var modeSettings: some View {
        switch configuration.mode {
        case .disabled:
            Text("This trackpad will not emit pointer, scroll, or button input.")
                .paddrTypography(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .mouse:
            VStack(spacing: PaddrStyle.settingsRowSpacing) {
                sensitivityRow
                ValueSliderRow(
                    title: "Center tap radius",
                    systemImage: "scope",
                    value: $configuration.mouseDeadzone,
                    range: ConfigurationLimits.mouseDeadzone,
                    step: 0.01,
                    valueText: configuration.mouseDeadzone.formatted(.percent.precision(.fractionLength(0)))
                )
                .help("The radius starts at the pad center. Movement pauses inside it, and leaving it cancels the tap.")
                TapActionPicker(selection: $configuration.tapKey)
            }

        case .scroll:
            VStack(spacing: PaddrStyle.settingsRowSpacing) {
                sensitivityRow
                TapActionPicker(selection: $configuration.tapKey)
            }

        case .dpad:
            ButtonZoneConfigurationView(configuration: $configuration)
        }
    }

    private var sensitivityRow: some View {
        ValueSliderRow(
            title: "Sensitivity",
            systemImage: "speedometer",
            value: $configuration.sensitivity,
            range: ConfigurationLimits.sensitivity,
            step: 0.1,
            valueText: configuration.sensitivity.formatted(.number.precision(.fractionLength(1))) + "×"
        )
    }
}
