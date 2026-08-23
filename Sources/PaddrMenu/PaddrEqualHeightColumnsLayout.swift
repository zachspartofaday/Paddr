import SwiftUI

/// Gives flexible columns one shared intrinsic height without accepting an
/// arbitrary height proposed by their host. This keeps peer cards aligned in a
/// tall scroll viewport while allowing each card to return to its natural
/// height when an adaptive parent switches to a vertical layout.
struct PaddrEqualHeightColumnsLayout: Layout {
    let spacing: CGFloat

    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let geometry = geometry(for: proposal.width, subviews: subviews)
        return CGSize(width: geometry.width, height: geometry.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let geometry = geometry(for: bounds.width, subviews: subviews)
        var x = bounds.minX

        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: geometry.columnWidth,
                    height: geometry.height
                )
            )
            x += geometry.columnWidth + spacing
        }
    }

    private func geometry(
        for proposedWidth: CGFloat?,
        subviews: Subviews
    ) -> (width: CGFloat, columnWidth: CGFloat, height: CGFloat) {
        let count = CGFloat(subviews.count)
        let totalSpacing = spacing * CGFloat(max(0, subviews.count - 1))
        let proposedWidth = proposedWidth.flatMap { width in
            width.isFinite ? max(0, width) : nil
        }

        let columnWidth: CGFloat
        let width: CGFloat
        if let proposedWidth {
            width = proposedWidth
            columnWidth = max(0, (proposedWidth - totalSpacing) / count)
        } else {
            columnWidth = subviews.reduce(CGFloat.zero) { currentMaximum, subview in
                max(
                    currentMaximum,
                    subview.sizeThatFits(.unspecified).width
                )
            }
            width = (columnWidth * count) + totalSpacing
        }

        let childProposal = ProposedViewSize(width: columnWidth, height: nil)
        let height = subviews.reduce(CGFloat.zero) { currentMaximum, subview in
            max(currentMaximum, subview.sizeThatFits(childProposal).height)
        }
        return (width, columnWidth, height)
    }
}
