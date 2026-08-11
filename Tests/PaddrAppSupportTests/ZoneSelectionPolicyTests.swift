import XCTest
@testable import PaddrAppSupport
import TrackIsBackCore

final class ZoneSelectionPolicyTests: XCTestCase {
    func testEveryLayoutNormalizesToAVisibleInitialZone() {
        for layout in PadZoneLayout.allCases {
            let initial = ZoneSelectionPolicy.normalized(.center, for: layout)
            XCTAssertTrue(layout.zones.contains(initial), "Invalid initial zone for \(layout.rawValue)")
            if layout != .gridNine {
                XCTAssertEqual(initial, layout.zones[0])
            }
        }
    }

    func testPreviousAndNextNavigationWrapForEveryLayout() {
        for layout in PadZoneLayout.allCases {
            let first = layout.zones[0]
            let previous = ZoneSelectionPolicy.moved(from: first, direction: .previous, in: layout)
            let next = ZoneSelectionPolicy.moved(from: layout.zones.last!, direction: .next, in: layout)
            XCTAssertEqual(previous, layout.zones.last)
            XCTAssertEqual(next, first)
        }
    }

    func testSpatialNavigationMatchesLayoutGeometry() {
        XCTAssertEqual(moved(.left, .right, .horizontalTwo), .right)
        XCTAssertEqual(moved(.right, .left, .horizontalTwo), .left)
        XCTAssertEqual(moved(.up, .down, .verticalTwo), .down)
        XCTAssertEqual(moved(.down, .up, .verticalTwo), .up)
        XCTAssertEqual(moved(.topLeft, .right, .fourCorners), .topRight)
        XCTAssertEqual(moved(.topRight, .down, .fourCorners), .bottomRight)
        XCTAssertEqual(moved(.left, .up, .radialFour), .up)
        XCTAssertEqual(moved(.up, .right, .radialFour), .right)
        XCTAssertEqual(moved(.center, .up, .gridNine), .up)
        XCTAssertEqual(moved(.center, .left, .gridNine), .left)
        XCTAssertEqual(moved(.center, .down, .gridNine), .down)
        XCTAssertEqual(moved(.center, .right, .gridNine), .right)
    }

    func testEveryVisibleZoneWritesTheBindingReadForThatLayout() {
        let bindings = ["q", "w", "e", "a", "s", "d", "z", "x", "c"]
        for layout in PadZoneLayout.allCases {
            var configuration = PadConfiguration(mode: .dpad, dpadDeadzone: 0, zoneLayout: layout)
            for (zone, binding) in zip(layout.zones, bindings) {
                configuration[bindingFor: zone] = binding
                XCTAssertEqual(configuration[bindingFor: zone], binding)
            }
        }
    }

    private func moved(
        _ zone: ButtonZone,
        _ direction: ZoneNavigationDirection,
        _ layout: PadZoneLayout
    ) -> ButtonZone {
        ZoneSelectionPolicy.moved(from: zone, direction: direction, in: layout)
    }
}
