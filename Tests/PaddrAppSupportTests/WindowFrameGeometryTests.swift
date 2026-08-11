import Foundation
import XCTest
@testable import PaddrAppSupport

final class WindowFrameGeometryTests: XCTestCase {
    func testContentHeightSubtractsWindowChromeFromVisibleHeight() {
        let result = WindowFrameGeometry.fittedContentHeight(
            requestedHeight: 900,
            currentFrame: CGRect(x: 0, y: 0, width: 1_120, height: 632),
            currentContentRect: CGRect(x: 0, y: 0, width: 1_120, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 800)
        )

        XCTAssertEqual(result, 768)
    }

    func testContentHeightPreservesARequestThatFits() {
        let result = WindowFrameGeometry.fittedContentHeight(
            requestedHeight: 640,
            currentFrame: CGRect(x: 0, y: 0, width: 1_120, height: 632),
            currentContentRect: CGRect(x: 0, y: 0, width: 1_120, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(result, 640)
    }

    func testFramePreservesItsTopEdgeWhenItFits() {
        let frame = WindowFrameGeometry.constrainedFrame(
            CGRect(x: 100, y: 0, width: 800, height: 500),
            preservingTopEdge: 760,
            within: CGRect(x: 0, y: 0, width: 1_200, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 260, width: 800, height: 500))
    }

    func testFrameClampsOversizedContentAndOriginToVisibleFrame() {
        let visible = CGRect(x: 50, y: 30, width: 700, height: 500)
        let frame = WindowFrameGeometry.constrainedFrame(
            CGRect(x: -100, y: -100, width: 900, height: 800),
            preservingTopEdge: 900,
            within: visible
        )

        XCTAssertEqual(frame, visible)
    }

    func testFrameReclampsForANewScreen() {
        let proposed = CGRect(x: 1_300, y: 300, width: 800, height: 500)
        let secondScreen = CGRect(x: -1_000, y: 40, width: 900, height: 700)
        let frame = WindowFrameGeometry.constrainedFrame(
            proposed,
            preservingTopEdge: proposed.maxY,
            within: secondScreen
        )

        XCTAssertTrue(secondScreen.contains(frame))
        XCTAssertEqual(frame.maxX, secondScreen.maxX)
        XCTAssertEqual(frame.maxY, secondScreen.maxY)
    }
}
