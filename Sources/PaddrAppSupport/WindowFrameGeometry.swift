import Foundation

public enum WindowFrameGeometry {
    public static func fittedLayoutHeight(
        requestedHeight: CGFloat,
        currentFrame: CGRect,
        currentLayoutRect: CGRect,
        visibleFrame: CGRect
    ) -> CGFloat {
        let chromeHeight = max(0, currentFrame.height - currentLayoutRect.height)
        let maximumLayoutHeight = max(0, visibleFrame.height - chromeHeight)
        return min(max(0, requestedHeight), maximumLayoutHeight)
    }

    public static func contentSize(
        forLayoutSize requestedSize: CGSize,
        currentContentRect: CGRect,
        currentLayoutRect: CGRect
    ) -> CGSize {
        let obscuredWidth = max(0, currentContentRect.width - currentLayoutRect.width)
        let obscuredHeight = max(0, currentContentRect.height - currentLayoutRect.height)
        return CGSize(
            width: max(0, requestedSize.width) + obscuredWidth,
            height: max(0, requestedSize.height) + obscuredHeight
        )
    }

    public static func constrainedFrame(
        _ proposedFrame: CGRect,
        preservingTopEdge preferredTopEdge: CGFloat,
        within visibleFrame: CGRect
    ) -> CGRect {
        var result = proposedFrame
        result.size.width = min(max(0, result.width), visibleFrame.width)
        result.size.height = min(max(0, result.height), visibleFrame.height)

        let maximumX = visibleFrame.maxX - result.width
        result.origin.x = min(max(result.minX, visibleFrame.minX), maximumX)

        let maximumY = visibleFrame.maxY - result.height
        let topAnchoredY = preferredTopEdge - result.height
        result.origin.y = min(max(topAnchoredY, visibleFrame.minY), maximumY)
        return result
    }
}
