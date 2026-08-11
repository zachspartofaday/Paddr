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
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            AdaptiveControlRow(title: "Area layout", systemImage: "square.grid.3x3") {
                Picker("Area layout", selection: $configuration.zoneLayout) {
                    ForEach(PadZoneLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 200)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    padMap.frame(width: 190, height: 170)
                    inspector.frame(width: 300)
                }
                VStack(alignment: .leading, spacing: 12) {
                    padMap.frame(width: 210, height: 180)
                    inspector
                }
            }
            .onChange(of: configuration.zoneLayout) { _, layout in
                selectedZone = ZoneSelectionPolicy.normalized(selectedZone, for: layout)
            }
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

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveControlRow(title: "Selected area", systemImage: selectedZone.systemImage) {
                Picker("Selected area", selection: $selectedZone) {
                    ForEach(configuration.zoneLayout.zones, id: \.self) { zone in
                        Label(zone.title, systemImage: zone.systemImage).tag(zone)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
                .accessibilityIdentifier("selected-area-picker")
                .help("Choose the trackpad area to configure.")
            }

            AdaptiveControlRow(title: "Action", systemImage: "keyboard") {
                OutputBindingPicker(selection: $configuration[bindingFor: selectedZone], width: 130)
            }

            if configuration.zoneLayout != .gridNine {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Center deadzone", systemImage: "circle.dotted")
                        .paddrTypography(.callout)
                        .fontWeight(.medium)
                    HStack(spacing: 8) {
                        Slider(
                            value: $configuration.dpadDeadzone,
                            in: 0...Double(1).nextDown,
                            step: 0.01
                        )
                        Text(configuration.dpadDeadzone.formatted(.percent.precision(.fractionLength(0))))
                            .paddrTypography(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .help("Touches inside the center deadzone do not emit a zone action.")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(.secondary.opacity(0.07), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
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
