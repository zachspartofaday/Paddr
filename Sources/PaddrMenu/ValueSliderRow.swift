import SwiftUI

extension Binding where Value == Double {
    /// Snaps writes to the given step without using `Slider(step:)`, which would
    /// draw tick marks under the track.
    func quantized(step: Double, in range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                let snapped = (newValue / step).rounded() * step
                wrappedValue = Swift.min(Swift.max(snapped, range.lowerBound), range.upperBound)
            }
        )
    }
}

struct ValueSliderRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        PaddrSettingsRow(
            title: title,
            systemImage: systemImage,
            labelWidth: PaddrStyle.Width.labelColumnWide
        ) {
            HStack(spacing: PaddrStyle.Spacing.s2) {
                Slider(value: $value.quantized(step: step, in: range), in: range)
                    .frame(minWidth: PaddrStyle.sliderMinimumWidth)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueText)
                Text(valueText)
                    .paddrTypography(.value)
                    .foregroundStyle(.secondary)
                    .frame(width: PaddrStyle.Width.readout, alignment: .trailing)
            }
        }
    }
}

struct ToggleValueSliderRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    @Binding var isEnabled: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    let accessibilityIdentifier: String

    var sliderAccessibilityValue: String { valueText }

    var body: some View {
        PaddrSettingsRow(
            title: title,
            systemImage: systemImage,
            labelWidth: PaddrStyle.Width.labelColumnWide
        ) {
            HStack(spacing: PaddrStyle.Spacing.s2) {
                Toggle(title, isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(title)
                    .accessibilityValue(
                        isEnabled
                            ? LocalizedStringResource("On")
                            : LocalizedStringResource("Off")
                    )
                    .accessibilityIdentifier(accessibilityIdentifier)
                Slider(value: $value.quantized(step: step, in: range), in: range)
                    .frame(minWidth: PaddrStyle.toggleSliderMinimumWidth)
                    .layoutPriority(1)
                    .disabled(!isEnabled)
                    .accessibilityLabel(title)
                    .accessibilityValue(sliderAccessibilityValue)
                    .accessibilityIdentifier(accessibilityIdentifier + ".strength")
                Text(valueText)
                    .paddrTypography(.value)
                    .foregroundStyle(.secondary)
                    .frame(width: PaddrStyle.Width.readout, alignment: .trailing)
            }
        }
    }
}
