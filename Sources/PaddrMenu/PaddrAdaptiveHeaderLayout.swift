import SwiftUI

/// Keeps a card title and its trailing control on one row when their intrinsic
/// widths fit, then moves that same control below the title at constrained widths.
/// A custom layout avoids mounting parallel copies of stateful native controls.
struct PaddrAdaptiveHeaderLayout: Layout {
    let spacing: CGFloat
    let layoutDirection: LayoutDirection

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let geometry = geometry(
            availableWidth: finiteWidth(proposal.width),
            subviews: subviews
        ) else {
            return .zero
        }

        return CGSize(
            width: finiteWidth(proposal.width) ?? geometry.contentWidth,
            height: geometry.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let geometry = geometry(
            availableWidth: bounds.width,
            subviews: subviews
        ) else {
            return
        }

        let titleX = leadingX(for: geometry.titleSize.width, in: bounds)
        if geometry.usesInlineLayout {
            subviews[0].place(
                at: CGPoint(
                    x: titleX,
                    y: bounds.midY - (geometry.titleSize.height / 2)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(geometry.titleSize)
            )
            subviews[1].place(
                at: CGPoint(
                    x: trailingX(for: geometry.controlSize.width, in: bounds),
                    y: bounds.midY - (geometry.controlSize.height / 2)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(geometry.controlSize)
            )
        } else {
            subviews[0].place(
                at: CGPoint(x: titleX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(geometry.titleSize)
            )
            subviews[1].place(
                at: CGPoint(
                    x: leadingX(for: geometry.controlSize.width, in: bounds),
                    y: bounds.minY + geometry.titleSize.height + spacing
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(geometry.controlSize)
            )
        }
    }

    private func geometry(
        availableWidth: CGFloat?,
        subviews: Subviews
    ) -> HeaderGeometry? {
        guard subviews.count == 2 else { return nil }

        let naturalTitleSize = subviews[0].sizeThatFits(.unspecified)
        let controlSize = subviews[1].sizeThatFits(.unspecified)
        let inlineWidth = naturalTitleSize.width + spacing + controlSize.width
        let availableWidth = availableWidth ?? inlineWidth
        let usesInlineLayout = availableWidth >= inlineWidth
        let titleSize = usesInlineLayout
            ? naturalTitleSize
            : subviews[0].sizeThatFits(
                ProposedViewSize(width: availableWidth, height: nil)
            )

        return HeaderGeometry(
            titleSize: titleSize,
            controlSize: controlSize,
            usesInlineLayout: usesInlineLayout,
            contentWidth: usesInlineLayout
                ? inlineWidth
                : max(titleSize.width, controlSize.width),
            height: usesInlineLayout
                ? max(titleSize.height, controlSize.height)
                : titleSize.height + spacing + controlSize.height
        )
    }

    private func finiteWidth(_ width: CGFloat?) -> CGFloat? {
        width.flatMap { $0.isFinite ? max(0, $0) : nil }
    }

    private func leadingX(for width: CGFloat, in bounds: CGRect) -> CGFloat {
        layoutDirection == .leftToRight ? bounds.minX : bounds.maxX - width
    }

    private func trailingX(for width: CGFloat, in bounds: CGRect) -> CGFloat {
        layoutDirection == .leftToRight ? bounds.maxX - width : bounds.minX
    }
}

private struct HeaderGeometry {
    let titleSize: CGSize
    let controlSize: CGSize
    let usesInlineLayout: Bool
    let contentWidth: CGFloat
    let height: CGFloat
}
