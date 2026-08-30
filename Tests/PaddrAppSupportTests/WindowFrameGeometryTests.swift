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

    func testFormerDefaultFrameGrowsToTheNewDefault() {
        XCTAssertEqual(
            WindowFrameGeometry.migratedUsableSize(
                restoredSize: CGSize(width: 1_280, height: 700),
                legacyDefaultSize: CGSize(width: 1_280, height: 700),
                newDefaultSize: CGSize(width: 1_280, height: 760),
                minimumSize: CGSize(width: 680, height: 600)
            ),
            CGSize(width: 1_280, height: 760)
        )
    }

    func testCustomFrameIsPreservedAboveTheNewMinimum() {
        XCTAssertEqual(
            WindowFrameGeometry.migratedUsableSize(
                restoredSize: CGSize(width: 1_410, height: 830),
                legacyDefaultSize: CGSize(width: 1_280, height: 700),
                newDefaultSize: CGSize(width: 1_280, height: 760),
                minimumSize: CGSize(width: 680, height: 600)
            ),
            CGSize(width: 1_410, height: 830)
        )
    }

    func testCustomFrameIsClampedToTheNewMinimum() {
        XCTAssertEqual(
            WindowFrameGeometry.migratedUsableSize(
                restoredSize: CGSize(width: 640, height: 520),
                legacyDefaultSize: CGSize(width: 1_280, height: 700),
                newDefaultSize: CGSize(width: 1_280, height: 760),
                minimumSize: CGSize(width: 680, height: 600)
            ),
            CGSize(width: 680, height: 600)
        )
    }
}
