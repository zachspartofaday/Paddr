import XCTest
@testable import TrackIsBackCore

final class OutputBindingPresentationTests: XCTestCase {
    func testKnownBindingsHaveLocalizedPresentation() {
        let knownBindings = [
            TapBindingCatalog.leftMouseButton, TapBindingCatalog.rightMouseButton,
            "up", "right", "down", "left", "space", "return", "tab", "escape",
            "delete", "shift", "control", "option", "command"
        ]

        for binding in knownBindings {
            XCTAssertNotNil(OutputBindingPresentation.localizedName(for: binding), binding)
        }
    }

    func testLiteralBindingsUseStableVerbatimPresentation() {
        XCTAssertNil(OutputBindingPresentation.localizedName(for: "w"))
        XCTAssertEqual(OutputBindingPresentation.verbatimName(for: "w"), "W")
        XCTAssertEqual(OutputBindingPresentation.verbatimName(for: "code:123"), "code:123")
    }
}
