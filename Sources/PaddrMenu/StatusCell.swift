import SwiftUI

struct StatusCell: View {
    private enum Value {
        case localized(LocalizedStringResource)
        case verbatim(String)
    }

    let title: LocalizedStringResource
    let systemImage: String
    let state: StatusBadgeState
    private let identifier: String
    private let value: Value
    private let explicitAccessibilityValue: String?

    init(
        title: LocalizedStringResource,
        value: LocalizedStringResource,
        systemImage: String,
        state: StatusBadgeState,
        identifier: String = "status"
    ) {
        self.title = title
        self.value = .localized(value)
        self.systemImage = systemImage
        self.state = state
        self.identifier = identifier
        explicitAccessibilityValue = nil
    }

    init(
        title: LocalizedStringResource,
        value: String,
        systemImage: String,
        state: StatusBadgeState,
        accessibilityValue: String? = nil,
        identifier: String = "status"
    ) {
        self.title = title
        self.value = .verbatim(value)
        self.systemImage = systemImage
        self.state = state
        self.identifier = identifier
        explicitAccessibilityValue = accessibilityValue
    }

    var body: some View {
        PaddrAppearanceReader { appearance in
            cell(appearance: appearance)
        }
    }

    private func cell(appearance: PaddrAppearance) -> some View {
        HStack(spacing: PaddrStyle.Spacing.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(state.color)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            HStack(spacing: PaddrStyle.Spacing.s2) {
                Text(title)
                    .paddrTypography(.rowLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                valueText
                    .paddrTypography(.value)
                    .foregroundStyle(state.textColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PaddrStyle.Inset.control)
        .frame(minHeight: PaddrStyle.Metrics.row)
        .background(
            state.color.opacity(0.12),
            in: .rect(cornerRadius: PaddrStyle.Radius.control)
        )
        .overlay {
            if appearance.hasIncreasedContrast || appearance.usesShapeDifferentiation {
                RoundedRectangle(cornerRadius: PaddrStyle.Radius.control)
                    .strokeBorder(state.color, lineWidth: appearance.strokeWidth)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .paddrAccessibilityID("status", identifier)
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
