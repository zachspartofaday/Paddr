import Foundation
import XCTest
@testable import PaddrAppSupport

final class WindowFrameGeometryTests: XCTestCase {
    func testFullSizeContentAddsTheTitlebarAndToolbarInsetToRequestedLayoutSize() {
        let result = WindowFrameGeometry.contentSize(
            forLayoutSize: CGSize(width: 1_280, height: 700),
            currentContentRect: CGRect(x: 0, y: 0, width: 1_280, height: 740),
            currentLayoutRect: CGRect(x: 0, y: 0, width: 1_280, height: 700)
        )

        XCTAssertEqual(result, CGSize(width: 1_280, height: 740))
    }

    func testTraditionalContentWithoutAnInternalChromeInsetKeepsRequestedLayoutSize() {
        let result = WindowFrameGeometry.contentSize(
            forLayoutSize: CGSize(width: 720, height: 480),
            currentContentRect: CGRect(x: 0, y: 0, width: 720, height: 480),
            currentLayoutRect: CGRect(x: 0, y: 0, width: 720, height: 480)
        )

        XCTAssertEqual(result, CGSize(width: 720, height: 480))
    }
}
