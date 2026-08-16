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

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(state.color)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(title)
                .paddrTypography(.caption)
                .foregroundStyle(.secondary)
            valueText
                .paddrTypography(.callout)
                .bold()
                .foregroundStyle(state.textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 32)
        .background(state.color.opacity(0.11), in: .capsule)
        .overlay {
            if colorSchemeContrast == .increased {
                Capsule().strokeBorder(state.color, lineWidth: 1.5)
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
