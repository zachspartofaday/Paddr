import XCTest
@testable import TrackIsBackCore

final class MapperTapPolicyTests: XCTestCase {
    func testOnlyPointerAndScrollAllowTouchTap() {
        XCTAssertFalse(PadMode.disabled.allowsTouchTap)
        XCTAssertTrue(PadMode.mouse.allowsTouchTap)
        XCTAssertTrue(PadMode.scroll.allowsTouchTap)
        XCTAssertFalse(PadMode.dpad.allowsTouchTap)
    }

    func testOffAndEveryZoneLayoutCannotTap() throws {
        let space = try KeyCatalog.resolve("space")
        for mode in [PadMode.disabled, .dpad] {
            for layout in PadZoneLayout.allCases {
                var mapper = PadMapper(
                    side: .left,
                    configuration: PadConfiguration(mode: mode, tapKey: "space", zoneLayout: layout)
                )
                _ = try mapper.process(sample(touched: true, time: 1))
                let release = try mapper.process(sample(touched: false, time: 2))
                XCTAssertFalse(release.contains(.key(space, isPressed: true)), "\(mode) / \(layout)")
            }
        }
    }

    func testScrollTapStillEmits() throws {
        var mapper = PadMapper(side: .left, configuration: .init(mode: .scroll, tapKey: "space"))
        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        let release = try mapper.process(sample(touched: false, time: 2_000_000))
        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(release, [.key(space, isPressed: true), .key(space, isPressed: false)])
    }

    private func sample(touched: Bool, time: UInt64) -> TrackpadSample {
        TrackpadSample(isTouched: touched, isClicked: false, x: 0, y: 0, pressure: 0, timestampNanoseconds: time)
    }
}
