import SwiftUI

struct AdaptiveControlRow<Control: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                label
                Spacer(minLength: 16)
                control()
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                control().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .paddrTypography(.callout)
            .fontWeight(.medium)
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
        AdaptiveControlRow(title: title, systemImage: systemImage) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 220)
                Text(valueText)
                    .paddrTypography(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 46, alignment: .trailing)
            }
        }
    }
}
