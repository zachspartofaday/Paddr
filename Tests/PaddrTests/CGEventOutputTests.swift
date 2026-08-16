#if canImport(CoreGraphics)
import CoreGraphics
import XCTest
@testable import TrackIsBackCore

final class CGEventOutputTests: XCTestCase {
    func testMouseButtonReleaseThrowsWhenCurrentLocationIsUnavailable() {
        let output = CGEventOutput(currentMouseLocation: { nil })

        XCTAssertThrowsError(
            try output.dispatch([.mouseButton(.left, isPressed: false)])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("mouse location"))
        }
    }
}
#endif
