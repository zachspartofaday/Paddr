import SwiftUI

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
            labelWidth: PaddrStyle.sliderLabelWidth
        ) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: PaddrStyle.sliderMinimumWidth)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueText)
                Text(valueText)
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 46, alignment: .trailing)
            }
        }
    }
}
