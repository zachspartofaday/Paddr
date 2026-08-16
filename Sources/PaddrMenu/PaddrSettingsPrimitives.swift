import AppKit
import SwiftUI

struct PaddrSectionContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        content()
            .padding(.horizontal, PaddrStyle.insetHorizontalPadding)
            .padding(.vertical, PaddrStyle.insetVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                reduceTransparency
                    ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                    : AnyShapeStyle(Color.primary.opacity(0.032)),
                in: .rect(cornerRadius: PaddrStyle.insetCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PaddrStyle.insetCornerRadius)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(
                            colorSchemeContrast == .increased ? 0.95 : 0.18
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
    }
}

struct PaddrInsetDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis = .horizontal

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Rectangle()
            .fill(
                Color(nsColor: .separatorColor).opacity(
                    colorSchemeContrast == .increased ? 0.9 : 0.34
                )
            )
            .frame(
                maxWidth: axis == .horizontal ? .infinity : 1,
                maxHeight: axis == .vertical ? .infinity : 1
            )
            .padding(
                axis == .horizontal ? .horizontal : .vertical,
                axis == .horizontal ? PaddrStyle.dividerInset : PaddrStyle.zoneDividerInset
            )
    }
}

struct PaddrSettingsRow<Control: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    let labelWidth: CGFloat
    @ViewBuilder let control: () -> Control

    init(
        title: LocalizedStringResource,
        systemImage: String,
        labelWidth: CGFloat = PaddrStyle.settingsLabelWidth,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.systemImage = systemImage
        self.labelWidth = labelWidth
        self.control = control
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaddrStyle.settingsControlSpacing) {
                label
                    .frame(width: labelWidth, alignment: .leading)
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                label
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PaddrStyle.settingsRowVerticalPadding)
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .paddrTypography(.callout)
    }
}
