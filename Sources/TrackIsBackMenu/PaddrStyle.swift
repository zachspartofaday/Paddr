import AppKit
import SwiftUI

enum PaddrTextRole {
    case title
    case padTitle
    case headline
    case callout
    case caption

    var font: Font {
        switch self {
        case .title: .title2.bold()
        case .padTitle: .title3.weight(.semibold)
        case .headline: .headline
        case .callout: .callout
        case .caption: .caption
        }
    }
}

enum PaddrStyle {
    static let accent = Color(red: 26.0 / 255.0, green: 159.0 / 255.0, blue: 1)
    static let active = Color(nsColor: .systemGreen)

    /// Green status text clears 4.5:1 in light appearance while retaining the
    /// brighter adaptive system green against dark backgrounds.
    static let activeText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemGreen
            : NSColor(srgbRed: 0, green: 0.42, blue: 0.18, alpha: 1)
    })

    /// Accent for text: the bright product accent reads at only ~2.8:1 against light
    /// backgrounds, so light appearance gets a darker variant that clears 4.5:1.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 26.0 / 255.0, green: 159.0 / 255.0, blue: 1, alpha: 1)
            : NSColor(srgbRed: 0, green: 0.42, blue: 0.75, alpha: 1)
    })

    /// Warning text partner to `accentText`: system orange also fails contrast on
    /// light backgrounds, so light appearance darkens it.
    static let warningText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemOrange
            : NSColor(srgbRed: 0.65, green: 0.32, blue: 0, alpha: 1)
    })
    static let defaultWindowSize = NSSize(width: 1_120, height: 600)
    static let minimumWindowSize = NSSize(width: 640, height: 360)
    static let padColumnWidth: CGFloat = 530
    static let zoneMapWidth: CGFloat = 190
    static let zoneMapHeight: CGFloat = 182
    static let padPreviewCornerRadius: CGFloat = 30
    static let zoneInspectorWidth: CGFloat = 266
    static let panelPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 16
    static let cardHeaderHeight: CGFloat = 28
    static let behaviorRowHeight: CGFloat = 28
    static let behaviorPickerWidth: CGFloat = 272
    static let insetCornerRadius: CGFloat = 12
    static let insetHorizontalPadding: CGFloat = 14
    static let insetVerticalPadding: CGFloat = 14
    static let insetHeaderHeight: CGFloat = 28
    static let insetHeaderContentSpacing: CGFloat = 14
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
    static let zoneDividerInset: CGFloat = 12
    static let zoneSubdivisionSpacing: CGFloat = 18
    static let commandBarMinimumHeight: CGFloat = 50
}

private struct PaddrTypographyModifier: ViewModifier {
    let role: PaddrTextRole
    func body(content: Content) -> some View { content.font(role.font) }
}

private struct PaddrCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(
                    Color(nsColor: .controlBackgroundColor),
                    in: .rect(cornerRadius: PaddrStyle.cardCornerRadius)
                )
            } else {
                content.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: PaddrStyle.cardCornerRadius)
                )
            }
        }
            .overlay {
                RoundedRectangle(cornerRadius: PaddrStyle.cardCornerRadius)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(
                            colorSchemeContrast == .increased ? 1 : 0.46
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
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
