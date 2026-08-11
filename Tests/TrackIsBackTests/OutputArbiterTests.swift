import XCTest
@testable import TrackIsBackCore

final class OutputArbiterTests: XCTestCase {
    func testOverlappingKeyOwnershipReleasesAfterLastOwner() throws {
        let key = try KeyCatalog.resolve("space")
        var arbiter = OutputArbiter()

        XCTAssertEqual(arbiter.process([.key(key, isPressed: true)], from: .leftPad), [.key(key, isPressed: true)])
        XCTAssertTrue(arbiter.process([.key(key, isPressed: true)], from: .rightPad).isEmpty)
        XCTAssertTrue(arbiter.process([.key(key, isPressed: false)], from: .leftPad).isEmpty)
        XCTAssertEqual(arbiter.process([.key(key, isPressed: false)], from: .rightPad), [.key(key, isPressed: false)])
    }

    func testOverlappingMouseOwnershipAndDuplicatePresses() {
        var arbiter = OutputArbiter()
        let down = TrackpadOutputAction.mouseButton(.left, isPressed: true)
        let up = TrackpadOutputAction.mouseButton(.left, isPressed: false)

        XCTAssertEqual(arbiter.process([down], from: .leftPad), [down])
        XCTAssertTrue(arbiter.process([down], from: .leftPad).isEmpty)
        XCTAssertTrue(arbiter.process([down], from: .rightPad).isEmpty)
        XCTAssertTrue(arbiter.process([up], from: .leftPad).isEmpty)
        XCTAssertEqual(arbiter.process([up], from: .rightPad), [up])
    }

    func testTapCannotInterruptHeldBinding() throws {
        let key = try KeyCatalog.resolve("return")
        var arbiter = OutputArbiter()
        _ = arbiter.process([.key(key, isPressed: true)], from: .leftPad)

        XCTAssertTrue(arbiter.process([
            .key(key, isPressed: true),
            .key(key, isPressed: false)
        ], from: .rightPad).isEmpty)
        XCTAssertEqual(arbiter.process([.key(key, isPressed: false)], from: .leftPad), [
            .key(key, isPressed: false)
        ])
    }

    func testCrossingZonesWithSameBindingDoesNotFlicker() throws {
        let key = try KeyCatalog.resolve("w")
        var arbiter = OutputArbiter()
        _ = arbiter.process([.key(key, isPressed: true)], from: .leftPad)

        XCTAssertTrue(arbiter.process([
            .key(key, isPressed: false),
            .key(key, isPressed: true)
        ], from: .leftPad).isEmpty)
        XCTAssertEqual(arbiter.process([.key(key, isPressed: false)], from: .leftPad), [
            .key(key, isPressed: false)
        ])
    }

    func testGlobalReleaseIsIdempotent() throws {
        let key = try KeyCatalog.resolve("a")
        var arbiter = OutputArbiter()
        _ = arbiter.process([.key(key, isPressed: true)], from: .leftPad)
        _ = arbiter.process([.mouseButton(.right, isPressed: true)], from: .rightPad)

        let releases = arbiter.releaseAll()
        XCTAssertEqual(releases.count, 2)
        XCTAssertTrue(releases.contains(.key(key, isPressed: false)))
        XCTAssertTrue(releases.contains(.mouseButton(.right, isPressed: false)))
        XCTAssertTrue(arbiter.releaseAll().isEmpty)
    }
}
