import CoreGraphics
import PaddrCore

public enum ZoneMapGeometry {
    /// Returns the region whose boundary can be stroked entirely inside the pad.
    ///
    /// Zone paths intentionally reach the pad's physical bounds so their fills tile without
    /// seams. A centered stroke on those same paths would be clipped at the outer edge. The
    /// intersection with this inset pad preserves every internal divider while moving only the
    /// rounded exterior contour far enough inward for the complete selection stroke to render.
    public static func selectedOutlineRegion(
        for zoneRegion: CGPath,
        in bounds: CGRect,
        cornerRadius: CGFloat,
        lineWidth: CGFloat
    ) -> CGPath {
        let maximumInset = max(0, min(bounds.width, bounds.height) / 2)
        let inset = min(max(0, lineWidth / 2), maximumInset)
        let insetBounds = bounds.insetBy(dx: inset, dy: inset)
        let insetCornerRadius = min(
            max(0, cornerRadius - inset),
            max(0, min(insetBounds.width, insetBounds.height) / 2)
        )
        let insetPad = CGPath(
            roundedRect: insetBounds,
            cornerWidth: insetCornerRadius,
            cornerHeight: insetCornerRadius,
            transform: nil
        )
        return zoneRegion.intersection(insetPad)
    }

    public static func neutralRect(
        in bounds: CGRect,
        deadzone: Double,
        layout: PadZoneLayout
    ) -> CGRect? {
        guard deadzone > 0, layout != .gridNine else { return nil }
        switch layout {
        case .horizontalTwo:
            let width = bounds.width * deadzone
            return CGRect(
                x: bounds.midX - width / 2,
                y: bounds.minY,
                width: width,
                height: bounds.height
            )
        case .verticalTwo:
            let height = bounds.height * deadzone
            return CGRect(
                x: bounds.minX,
                y: bounds.midY - height / 2,
                width: bounds.width,
                height: height
            )
        case .radialFour, .fourCorners:
            let width = bounds.width * deadzone
            let height = bounds.height * deadzone
            return CGRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - height / 2,
                width: width,
                height: height
            )
        case .gridNine:
            return nil
        }
    }
}
