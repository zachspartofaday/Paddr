import Foundation

public enum WindowFrameGeometry {
    /// Fits only defaults; custom restored sizes must not pass through this policy.
    public static func fittedDefaultUsableSize(
        requestedSize: CGSize,
        minimumSize: CGSize,
        currentFrame: CGRect,
        currentLayoutRect: CGRect,
        visibleFrame: CGRect
    ) -> CGSize {
        let chromeWidth = max(0, currentFrame.width - currentLayoutRect.width)
        let chromeHeight = max(0, currentFrame.height - currentLayoutRect.height)
        return CGSize(
            width: max(minimumSize.width, min(requestedSize.width, visibleFrame.width - chromeWidth)),
            height: max(minimumSize.height, min(requestedSize.height, visibleFrame.height - chromeHeight))
        )
    }

    public static func constrainedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        var constrained = frame
        if frame.width <= visibleFrame.width {
            constrained.origin.x = min(
                max(frame.minX, visibleFrame.minX),
                visibleFrame.maxX - frame.width
            )
        } else {
            constrained.origin.x = visibleFrame.minX
        }
        if frame.height <= visibleFrame.height {
            constrained.origin.y = min(
                max(frame.minY, visibleFrame.minY),
                visibleFrame.maxY - frame.height
            )
        } else {
            constrained.origin.y = visibleFrame.maxY - frame.height
        }
        return constrained
    }

    public static func migratedUsableSize(
        restoredSize: CGSize,
        legacyDefaultSize: CGSize,
        newDefaultSize: CGSize,
        minimumSize: CGSize,
        tolerance: CGFloat = 0.5
    ) -> CGSize {
        let matchesLegacyDefault = abs(restoredSize.width - legacyDefaultSize.width) <= tolerance
            && abs(restoredSize.height - legacyDefaultSize.height) <= tolerance
        let preferredSize = matchesLegacyDefault ? newDefaultSize : restoredSize
        return CGSize(
            width: max(preferredSize.width, minimumSize.width),
            height: max(preferredSize.height, minimumSize.height)
        )
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
}
