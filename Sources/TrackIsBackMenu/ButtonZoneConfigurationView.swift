import PaddrAppSupport
import SwiftUI
import TrackIsBackCore

struct ButtonZoneConfigurationView: View {
    @Binding var configuration: PadConfiguration
    @State private var selectedZone: ButtonZone

    init(configuration: Binding<PadConfiguration>) {
        _configuration = configuration
        _selectedZone = State(
            initialValue: configuration.wrappedValue.zoneLayout.zones[0]
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                mapSection.frame(width: PaddrStyle.zoneMapWidth)
                PaddrInsetDivider(axis: .vertical)
                    .padding(.horizontal, 6)
                inspector.frame(width: PaddrStyle.zoneInspectorWidth)
            }

            VStack(alignment: .leading, spacing: 0) {
                mapSection
                PaddrInsetDivider()
                    .padding(.vertical, PaddrStyle.dividerBottomSpacing)
                inspector
            }
        }
        .onChange(of: configuration.zoneLayout) { _, layout in
            selectedZone = ZoneSelectionPolicy.normalized(selectedZone, for: layout)
        }
    }

    private var padMap: some View {
        ZonePadMap(
            layout: configuration.zoneLayout,
            deadzone: configuration.dpadDeadzone,
            configuration: configuration,
            selection: $selectedZone
        )
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.settingsRowSpacing) {
            Text("Area map")
                .paddrTypography(.callout)
                .bold()
                .frame(minHeight: PaddrStyle.insetHeaderHeight)
            padMap.frame(
                maxWidth: .infinity,
                minHeight: PaddrStyle.zoneMapHeight,
                maxHeight: PaddrStyle.zoneMapHeight
            )
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaddrStyle.settingsControlSpacing) {
                    selectedAreaTitle
                    Spacer(minLength: PaddrStyle.settingsControlSpacing)
                    selectedAreaPicker
                }

                VStack(alignment: .leading, spacing: 8) {
                    selectedAreaTitle
                    selectedAreaPicker.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(minHeight: PaddrStyle.insetHeaderHeight)
            .frame(maxWidth: .infinity)

            PaddrInsetDivider()
                .padding(.top, PaddrStyle.dividerTopSpacing)
                .padding(.bottom, PaddrStyle.dividerBottomSpacing)

            PaddrSettingsRow(title: "Action", systemImage: "keyboard") {
                OutputBindingPicker(
                    selection: $configuration[bindingFor: selectedZone],
                    width: PaddrStyle.compactPickerWidth
                )
            }

            if configuration.zoneLayout != .gridNine {
                PaddrSettingsRow(title: "Neutral zone", systemImage: "circle.dotted") {
                    HStack(spacing: 8) {
                        Slider(
                            value: $configuration.dpadDeadzone,
                            in: 0...Double(1).nextDown,
                            step: 0.01
                        )
                        .accessibilityLabel("Neutral zone size")
                        .accessibilityValue(
                            configuration.dpadDeadzone.formatted(.percent.precision(.fractionLength(0)))
                        )
                        .help("Touches inside the neutral zone do not emit an action.")
                        Text(configuration.dpadDeadzone.formatted(.percent.precision(.fractionLength(0))))
                            .paddrTypography(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .padding(.top, PaddrStyle.settingsRowSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var selectedAreaTitle: some View {
        Text("Selected area")
            .paddrTypography(.callout)
            .bold()
    }

    private var selectedAreaPicker: some View {
        Picker("Selected area", selection: $selectedZone) {
            ForEach(configuration.zoneLayout.zones, id: \.self) { zone in
                Label(zone.title, systemImage: zone.systemImage).tag(zone)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: PaddrStyle.compactPickerWidth, alignment: .trailing)
        .accessibilityIdentifier("selected-area-picker")
        .help("Choose the trackpad area to configure.")
    }
}

extension ButtonZone {
    var title: LocalizedStringResource {
        switch self {
        case .topLeft: LocalizedStringResource("Top left")
        case .up: LocalizedStringResource("Top")
        case .topRight: LocalizedStringResource("Top right")
        case .left: LocalizedStringResource("Left")
        case .center: LocalizedStringResource("Center")
        case .right: LocalizedStringResource("Right")
        case .bottomLeft: LocalizedStringResource("Bottom left")
        case .down: LocalizedStringResource("Bottom")
        case .bottomRight: LocalizedStringResource("Bottom right")
        }
    }

    var systemImage: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .up: "arrow.up"
        case .topRight: "arrow.up.right"
        case .left: "arrow.left"
        case .center: "circle"
        case .right: "arrow.right"
        case .bottomLeft: "arrow.down.left"
        case .down: "arrow.down"
        case .bottomRight: "arrow.down.right"
        }
    }
}
