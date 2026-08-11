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
                }
                .frame(maxWidth: .infinity, minHeight: PaddrStyle.behaviorRowHeight)
                .padding(.horizontal, PaddrStyle.insetHorizontalPadding)

                PaddrSectionContainer(
                    title: settingsTitle,
                    accessory: {
                        if configuration.mode == .dpad {
                            areaLayoutPicker
                        }
                    }
                ) {
                    modeSettings
                }
            }
            .padding(.top, PaddrStyle.settingsRowSpacing)
        } label: {
            HStack(spacing: 10) {
                Text(title).paddrTypography(.padTitle)
                Spacer()
                Text(summary)
                    .paddrTypography(.caption)
                    .foregroundStyle(
                        configuration.mode == .disabled ? Color.secondary : PaddrStyle.accentText
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        configuration.mode == .disabled
                            ? Color.secondary.opacity(0.08)
                            : PaddrStyle.accent.opacity(0.10),
                        in: .capsule
                    )
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
            previewSplit(previewTitle: LocalizedStringResource("Preview")) {
                Text("This trackpad will not emit pointer, scroll, or button input.")
                    .paddrTypography(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .mouse:
            previewSplit(previewTitle: LocalizedStringResource("Tap area")) {
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
            }

        case .scroll:
            previewSplit(previewTitle: LocalizedStringResource("Preview")) {
                VStack(spacing: PaddrStyle.settingsRowSpacing) {
                    sensitivityRow
                    TapActionPicker(selection: $configuration.tapKey)
                }
            }

        case .dpad:
            ButtonZoneConfigurationView(configuration: $configuration)
        }
    }

    /// Mirrors the Zones map-plus-inspector split so every mode keeps the pad
    /// itself as the card's anchor.
    private func previewSplit(
        previewTitle: LocalizedStringResource,
        @ViewBuilder settings: @escaping () -> some View
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                previewSection(title: previewTitle)
                    .frame(width: PaddrStyle.zoneMapWidth)
                PaddrInsetDivider(axis: .vertical)
                    .padding(.horizontal, 8)
                settings()
                    .frame(width: PaddrStyle.zoneInspectorWidth, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: PaddrStyle.zoneSubdivisionSpacing) {
                previewSection(title: previewTitle)
                settings()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func previewSection(title: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaddrStyle.settingsRowSpacing) {
            Text(title)
                .paddrTypography(.callout)
                .bold()
                .frame(minHeight: PaddrStyle.insetHeaderHeight)
            PadModePreview(mode: configuration.mode, deadzone: configuration.mouseDeadzone)
                .frame(maxWidth: PaddrStyle.zoneMapWidth * 1.4)
                .frame(
                    minHeight: PaddrStyle.zoneMapHeight,
                    maxHeight: PaddrStyle.zoneMapHeight
                )
                .help("Mirrors how the trackpad will respond in this mode.")
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

    private var areaLayoutPicker: some View {
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
