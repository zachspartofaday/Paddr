import Foundation

public enum WindowFrameGeometry {
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
}
