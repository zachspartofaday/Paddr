import SwiftUI

/// Keeps compact, intrinsic-width items on one line when they fit and moves whole items
/// to the next line when they do not. This preserves readable status text at narrow widths
/// instead of shrinking or truncating individual pills.
struct PaddrWrappingHStack: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let naturalWidth = sizes.reduce(0) { width, size in
            width + size.width
        } + (horizontalSpacing * CGFloat(max(0, sizes.count - 1)))
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let availableWidth = proposedWidth ?? naturalWidth
        let result = arrangement(for: sizes, availableWidth: availableWidth)

        return CGSize(
            width: proposedWidth ?? result.size.width,
            height: result.size.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = arrangement(for: sizes, availableWidth: bounds.width)

        for (index, origin) in result.origins.enumerated() {
            let size = sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func arrangement(
        for sizes: [CGSize],
        availableWidth: CGFloat
    ) -> (size: CGSize, origins: [CGPoint]) {
        guard !sizes.isEmpty else { return (.zero, []) }

        var origins: [CGPoint] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for size in sizes {
            let originX = cursorX == 0 ? 0 : cursorX + horizontalSpacing
            if cursorX > 0, originX + size.width > availableWidth {
                cursorY += rowHeight + verticalSpacing
                cursorX = 0
                rowHeight = 0
            }

            let placedX = cursorX == 0 ? 0 : cursorX + horizontalSpacing
            origins.append(CGPoint(x: placedX, y: cursorY))
            cursorX = placedX + size.width
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, cursorX)
        }

        return (
            CGSize(width: usedWidth, height: cursorY + rowHeight),
            origins
        )
    }
}
