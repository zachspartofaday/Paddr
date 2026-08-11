import AppKit
import SwiftUI

enum PaddrTextRole {
    case title
    case headline
    case callout
    case caption

    var font: Font {
        switch self {
        case .title: .title2.bold()
        case .headline: .headline
        case .callout: .callout
        case .caption: .caption
        }
    }
}

enum PaddrStyle {
    static let accent = Color(red: 26.0 / 255.0, green: 159.0 / 255.0, blue: 1)
    static let defaultWindowSize = NSSize(width: 1_120, height: 600)
    static let minimumWindowSize = NSSize(width: 640, height: 360)
    static let padColumnWidth: CGFloat = 530
    static let zoneMapWidth: CGFloat = 196
    static let zoneMapHeight: CGFloat = 182
    static let zoneInspectorWidth: CGFloat = 265
    static let panelPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let cardHeaderHeight: CGFloat = 28
    static let behaviorRowHeight: CGFloat = 28
    static let insetCornerRadius: CGFloat = 12
    static let insetHorizontalPadding: CGFloat = 14
    static let insetVerticalPadding: CGFloat = 14
    static let insetHeaderHeight: CGFloat = 28
    static let settingsLabelWidth: CGFloat = 108
    static let sliderLabelWidth: CGFloat = 152
    static let sliderMinimumWidth: CGFloat = 160
    static let settingsControlSpacing: CGFloat = 12
    static let settingsRowSpacing: CGFloat = 12
    static let settingsRowVerticalPadding: CGFloat = 2
    static let compactPickerWidth: CGFloat = 130
    static let dividerInset: CGFloat = 8
    static let dividerTopSpacing: CGFloat = 8
    static let dividerBottomSpacing: CGFloat = 12
}

private struct PaddrTypographyModifier: ViewModifier {
    let role: PaddrTextRole
    func body(content: Content) -> some View { content.font(role.font) }
}

private struct PaddrCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: PaddrStyle.cardCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PaddrStyle.cardCornerRadius)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(
                            colorSchemeContrast == .increased ? 1 : 0.72
                        ),
                        lineWidth: 1
                    )
            }
    }
}

private struct PaddrActionButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .font(.callout)
                .tint(PaddrStyle.accent)
        } else {
            content.buttonStyle(.glass).controlSize(.regular).font(.callout)
        }
    }
}

extension View {
    func paddrTypography(_ role: PaddrTextRole) -> some View {
        modifier(PaddrTypographyModifier(role: role))
    }

    func paddrCard() -> some View { modifier(PaddrCardModifier()) }

    func paddrActionButton(prominent: Bool = false) -> some View {
        modifier(PaddrActionButtonModifier(prominent: prominent))
    }
}
