import Foundation

public enum WindowFrameGeometry {
    public static func fittedContentHeight(
        requestedHeight: CGFloat,
        currentFrame: CGRect,
        currentContentRect: CGRect,
        visibleFrame: CGRect
    ) -> CGFloat {
        let chromeHeight = max(0, currentFrame.height - currentContentRect.height)
        let maximumContentHeight = max(0, visibleFrame.height - chromeHeight)
        return min(max(0, requestedHeight), maximumContentHeight)
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
