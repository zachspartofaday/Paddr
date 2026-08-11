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
    static let defaultWindowSize = NSSize(width: 1_120, height: 680)
    static let minimumWindowSize = NSSize(width: 640, height: 620)
    static let padColumnWidth: CGFloat = 530
    static let panelPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
}

private struct PaddrTypographyModifier: ViewModifier {
    let role: PaddrTextRole
    func body(content: Content) -> some View { content.font(role.font) }
}

private struct PaddrCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial),
                in: .rect(cornerRadius: PaddrStyle.cardCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PaddrStyle.cardCornerRadius)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
    }
}

private struct PaddrActionButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent).controlSize(.regular).font(.callout.weight(.semibold))
        } else {
            content.buttonStyle(.glass).controlSize(.regular).font(.callout.weight(.medium))
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
