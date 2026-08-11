import SwiftUI

struct ValueSliderRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .frame(minWidth: 245)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .controlSize(.regular)
    }
}
