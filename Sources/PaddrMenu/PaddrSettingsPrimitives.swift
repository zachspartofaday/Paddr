import AppKit
import SwiftUI

struct PaddrSectionContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        PaddrAppearanceReader { appearance in
            content()
                .padding(.horizontal, PaddrStyle.Spacing.s3)
                .padding(.vertical, PaddrStyle.Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    appearance.usesOpaqueFallback
                        ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                        : AnyShapeStyle(Color.primary.opacity(0.032)),
                    in: .rect(cornerRadius: PaddrStyle.Radius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PaddrStyle.Radius.control)
                        .strokeBorder(
                            Color(nsColor: .separatorColor)
                                .opacity(appearance.strokeOpacity(0.18)),
                            lineWidth: appearance.strokeWidth
                        )
                }
        }
    }
}

struct PaddrInsetDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis = .horizontal

    var body: some View {
        PaddrAppearanceReader { appearance in
            Rectangle()
                .fill(
                    Color(nsColor: .separatorColor)
                        .opacity(appearance.strokeOpacity(0.34))
                )
                .frame(
                    maxWidth: axis == .horizontal ? .infinity : 1,
                    maxHeight: axis == .vertical ? .infinity : 1
                )
                .padding(
                    axis == .horizontal ? .horizontal : .vertical,
                    axis == .horizontal ? PaddrStyle.Spacing.s2 : PaddrStyle.Spacing.s3
                )
        }
    }
}

/// The single settings-row grammar: a fixed label column carrying an SF Symbol, and a
/// trailing control column, on the shared `Metrics.row` height family.
struct PaddrSettingsRow<Control: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    /// Picker rows and slider rows need different label columns; see `PaddrStyle.Width`.
    var labelWidth: CGFloat = PaddrStyle.Width.labelColumn
    @ViewBuilder let control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PaddrStyle.Spacing.s3) {
                label
                    .frame(width: labelWidth, alignment: .leading)
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s2) {
                label
                control()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaddrStyle.Metrics.row, alignment: .leading)
        .padding(.vertical, PaddrStyle.Spacing.s1)
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .paddrTypography(.rowLabel)
    }
}

/// Lays out settings rows on the shared row spacing, and carries the inset divider that
/// separates one declared group from the group above it, so call sites stop hand-placing
/// dividers and one-off top padding.
struct PaddrSettingsGroup<Content: View>: View {
    var showsLeadingDivider: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            if showsLeadingDivider {
                PaddrInsetDivider()
            }
            content()
        }
    }
}
