import CoreGraphics
import XCTest
@testable import PaddrAppSupport
import PaddrCore

final class ZoneMapGeometryTests: XCTestCase {
    func testRadialNeutralPreviewPreservesRuntimeNormalizedRadius() throws {
        let bounds = CGRect(x: 0, y: 0, width: 230, height: 190)
        let rect = try XCTUnwrap(
            ZoneMapGeometry.neutralRect(in: bounds, deadzone: 0.5, layout: .radialFour)
        )

        XCTAssertEqual(rect.width, 115)
        XCTAssertEqual(rect.height, 95)
        XCTAssertEqual(rect.midX, bounds.midX)
        XCTAssertEqual(rect.midY, bounds.midY)
    }

    func testLinearAndGridNeutralPreviewGeometry() throws {
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 100)
        XCTAssertEqual(
            ZoneMapGeometry.neutralRect(in: bounds, deadzone: 0.2, layout: .horizontalTwo),
            CGRect(x: 90, y: 20, width: 40, height: 100)
        )
        XCTAssertEqual(
            ZoneMapGeometry.neutralRect(in: bounds, deadzone: 0.2, layout: .verticalTwo),
            CGRect(x: 10, y: 60, width: 200, height: 20)
        )
        XCTAssertNil(ZoneMapGeometry.neutralRect(in: bounds, deadzone: 0.2, layout: .gridNine))
    }
}
