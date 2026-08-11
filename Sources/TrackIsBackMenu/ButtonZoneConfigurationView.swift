import SwiftUI
import TrackIsBackCore

struct ButtonZoneConfigurationView: View {
    @Binding var configuration: PadConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            LabeledContent {
                Picker("Area layout", selection: $configuration.zoneLayout) {
                    ForEach(PadZoneLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.regular)
                .frame(minWidth: 180)
            } label: {
                Label("Area layout", systemImage: "square.grid.3x3")
            }

            ZonePreview(configuration: configuration)

            if configuration.zoneLayout != .gridNine {
                ValueSliderRow(
                    title: "Neutral zone",
                    systemImage: "circle.dashed",
                    value: $configuration.dpadDeadzone,
                    range: 0...0.6,
                    step: 0.01,
                    valueText: configuration.dpadDeadzone.formatted(.percent.precision(.fractionLength(0)))
                )
            }

            ZoneKeyAssignmentsView(configuration: $configuration)
        }
    }
}
