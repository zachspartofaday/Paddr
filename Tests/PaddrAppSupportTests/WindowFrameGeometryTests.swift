import Foundation
import XCTest
@testable import PaddrAppSupport

final class WindowFrameGeometryTests: XCTestCase {
    func testDefaultFitsAvailableScreenUsingMeasuredChrome() {
        for (screen, expected) in [
            (CGSize(width: 1800, height: 1200), CGSize(width: 1380, height: 1040)),
            (CGSize(width: 1200, height: 900), CGSize(width: 1190, height: 862)),
            (CGSize(width: 600, height: 500), CGSize(width: 680, height: 600))
        ] {
            XCTAssertEqual(WindowFrameGeometry.fittedDefaultUsableSize(
                requestedSize: CGSize(width: 1380, height: 1040),
                minimumSize: CGSize(width: 680, height: 600),
                currentFrame: CGRect(x: 0, y: 0, width: 1290, height: 798),
                currentLayoutRect: CGRect(x: 0, y: 0, width: 1280, height: 760),
                visibleFrame: CGRect(origin: CGPoint(x: -1200, y: 40), size: screen)
            ), expected)
        }
    }

    func testScreenBelowMinimumPreservesMinimumAndAlignsTopEdge() {
        let screen = CGRect(x: -600, y: 40, width: 600, height: 500)
        let result = WindowFrameGeometry.constrainedFrame(
            CGRect(x: 0, y: 0, width: 680, height: 638), to: screen
        )
        XCTAssertEqual(result.size, CGSize(width: 680, height: 638))
        XCTAssertEqual(result.minX, screen.minX)
        XCTAssertEqual(result.maxY, screen.maxY)
    }

    func testEnlargedFrameIsMovedInsideTheVisibleScreenWithoutChangingItsSize() {
        let frame = CGRect(x: 500, y: -80, width: 680, height: 600)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)

        let result = WindowFrameGeometry.constrainedFrame(frame, to: visibleFrame)

        XCTAssertEqual(result, CGRect(x: 500, y: 0, width: 680, height: 600))
    }

    func testFrameThatAlreadyFitsKeepsItsPreferredTopEdgeAndOrigin() {
        let frame = CGRect(x: 120, y: 140, width: 1_280, height: 760)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)

        XCTAssertEqual(
            WindowFrameGeometry.constrainedFrame(frame, to: visibleFrame),
            frame
        )
    }

    func testOversizedFrameKeepsItsTitleBarAtTheVisibleTopEdge() {
        let frame = CGRect(x: 80, y: 0, width: 680, height: 1_000)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 800)

        let result = WindowFrameGeometry.constrainedFrame(frame, to: visibleFrame)

        XCTAssertEqual(result, CGRect(x: 80, y: -200, width: 680, height: 1_000))
        XCTAssertEqual(result.maxY, visibleFrame.maxY)
    }

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
                restoredSize: CGSize(width: 1_280, height: 760),
                legacyDefaultSize: CGSize(width: 1_280, height: 760),
                newDefaultSize: CGSize(width: 1_380, height: 1_040),
                minimumSize: CGSize(width: 680, height: 600)
            ),
            CGSize(width: 1_380, height: 1_040)
        )
    }

    func testCustomFrameIsPreservedAboveTheNewMinimum() {
        XCTAssertEqual(
            WindowFrameGeometry.migratedUsableSize(
                restoredSize: CGSize(width: 1_410, height: 830),
                legacyDefaultSize: CGSize(width: 1_280, height: 760),
                newDefaultSize: CGSize(width: 1_380, height: 1_040),
                minimumSize: CGSize(width: 680, height: 600)
            ),
            CGSize(width: 1_410, height: 830)
        )
    }

    func testCustomFrameIsClampedToTheNewMinimum() {
        XCTAssertEqual(
            WindowFrameGeometry.migratedUsableSize(
                restoredSize: CGSize(width: 640, height: 520),
                legacyDefaultSize: CGSize(width: 1_280, height: 760),
                newDefaultSize: CGSize(width: 1_380, height: 1_040),
                minimumSize: CGSize(width: 680, height: 600)
            ),
            CGSize(width: 680, height: 600)
        )
    }
}
