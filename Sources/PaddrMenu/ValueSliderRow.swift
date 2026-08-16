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
        PaddrSettingsRow(title: title, systemImage: systemImage) {
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
