import Foundation

public enum WindowFrameGeometry {
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
