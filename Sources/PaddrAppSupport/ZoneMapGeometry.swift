import CoreGraphics
import TrackIsBackCore

public enum ZoneMapGeometry {
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
