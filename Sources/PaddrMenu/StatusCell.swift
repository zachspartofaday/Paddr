import SwiftUI

struct StatusCell: View {
    private enum Value {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let title: LocalizedStringResource
    let systemImage: String
    let state: StatusBadgeState
    private let value: Value
    private let explicitAccessibilityValue: String?

    init(
        title: LocalizedStringResource,
        value: LocalizedStringResource,
        systemImage: String,
        state: StatusBadgeState
    ) {
        self.title = title
        self.value = .localized(value)
        self.systemImage = systemImage
        self.state = state
        explicitAccessibilityValue = nil
    }

    init(
        title: LocalizedStringResource,
        value: String,
        systemImage: String,
        state: StatusBadgeState,
        accessibilityValue: String? = nil
    ) {
        self.title = title
        self.value = .verbatim(value)
        self.systemImage = systemImage
        self.state = state
        explicitAccessibilityValue = accessibilityValue
    }

    var body: some View {
        PaddrAppearanceReader { appearance in
            cell(appearance: appearance)
        }
    }

    private func cell(appearance: PaddrAppearance) -> some View {
        HStack(spacing: PaddrStyle.Spacing.s1) {
            Image(systemName: systemImage)
                .foregroundStyle(state.color)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(title)
                .paddrTypography(.caption)
                .foregroundStyle(.secondary)
            valueText
                .paddrTypography(.value)
                .foregroundStyle(state.textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, PaddrStyle.Spacing.s1)
        .frame(minHeight: PaddrStyle.Metrics.row)
        // The wash, not the icon colour at an opacity: the icon and the value are derived
        // against this wash, so it has to be the raw colour and it has to carry the same
        // opacity the derivation used.
        .background(state.tint, in: .capsule)
        .overlay {
            if appearance.hasIncreasedContrast {
                Capsule().strokeBorder(state.color, lineWidth: appearance.strokeWidth)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var valueText: some View {
        switch value {
        case let .localized(resource): Text(resource)
        case let .verbatim(string): Text(verbatim: string)
        }
    }

    private var accessibilityValue: Text {
        if let explicitAccessibilityValue {
            return Text(verbatim: explicitAccessibilityValue)
        }
        switch value {
        case let .localized(resource): return Text(resource)
        case let .verbatim(string): return Text(verbatim: string)
        }
    }
}
