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

    func testRadialFourDirectionalNavigationFromEveryZone() {
        assertDirectionalNavigation(from: .up, in: .radialFour, left: .left, right: .right, up: .up, down: .down)
        assertDirectionalNavigation(from: .right, in: .radialFour, left: .left, right: .right, up: .up, down: .down)
        assertDirectionalNavigation(from: .down, in: .radialFour, left: .left, right: .right, up: .up, down: .down)
        assertDirectionalNavigation(from: .left, in: .radialFour, left: .left, right: .right, up: .up, down: .down)
    }

    func testFourCornersDirectionalNavigationFromEveryZone() {
        assertDirectionalNavigation(
            from: .topLeft,
            in: .fourCorners,
            left: .topLeft,
            right: .topRight,
            up: .topLeft,
            down: .bottomLeft
        )
        assertDirectionalNavigation(
            from: .topRight,
            in: .fourCorners,
            left: .topLeft,
            right: .topRight,
            up: .topRight,
            down: .bottomRight
        )
        assertDirectionalNavigation(
            from: .bottomRight,
            in: .fourCorners,
            left: .bottomLeft,
            right: .bottomRight,
            up: .topRight,
            down: .bottomRight
        )
        assertDirectionalNavigation(
            from: .bottomLeft,
            in: .fourCorners,
            left: .bottomLeft,
            right: .bottomRight,
            up: .topLeft,
            down: .bottomLeft
        )
    }

    func testHorizontalTwoDirectionalNavigationFromEveryZone() {
        assertDirectionalNavigation(from: .left, in: .horizontalTwo, left: .left, right: .right, up: .left, down: .left)
        assertDirectionalNavigation(from: .right, in: .horizontalTwo, left: .left, right: .right, up: .right, down: .right)
    }

    func testVerticalTwoDirectionalNavigationFromEveryZone() {
        assertDirectionalNavigation(from: .up, in: .verticalTwo, left: .up, right: .up, up: .up, down: .down)
        assertDirectionalNavigation(from: .down, in: .verticalTwo, left: .down, right: .down, up: .up, down: .down)
    }

    func testGridNineDirectionalNavigationFromEveryZone() {
        assertDirectionalNavigation(from: .topLeft, in: .gridNine, left: .topLeft, right: .up, up: .topLeft, down: .left)
        assertDirectionalNavigation(from: .up, in: .gridNine, left: .topLeft, right: .topRight, up: .up, down: .center)
        assertDirectionalNavigation(from: .topRight, in: .gridNine, left: .up, right: .topRight, up: .topRight, down: .right)
        assertDirectionalNavigation(from: .left, in: .gridNine, left: .left, right: .center, up: .topLeft, down: .bottomLeft)
        assertDirectionalNavigation(from: .center, in: .gridNine, left: .left, right: .right, up: .up, down: .down)
        assertDirectionalNavigation(from: .right, in: .gridNine, left: .center, right: .right, up: .topRight, down: .bottomRight)
        assertDirectionalNavigation(from: .bottomLeft, in: .gridNine, left: .bottomLeft, right: .down, up: .left, down: .bottomLeft)
        assertDirectionalNavigation(from: .down, in: .gridNine, left: .bottomLeft, right: .bottomRight, up: .center, down: .down)
        assertDirectionalNavigation(from: .bottomRight, in: .gridNine, left: .down, right: .bottomRight, up: .right, down: .bottomRight)
    }

    func testEveryVisibleZoneWritesTheBindingReadForThatLayout() throws {
        let bindings = ["q", "w", "e", "a", "s", "d", "z", "x", "c"]
        for layout in PadZoneLayout.allCases {
            var configuration = PadConfiguration(mode: .dpad, dpadDeadzone: 0, zoneLayout: layout)
            for (zone, binding) in zip(layout.zones, bindings) {
                configuration[bindingFor: zone] = binding
            }

            let expectedBindings = Array(bindings.prefix(layout.zones.count))
            for (zone, binding) in zip(layout.zones, expectedBindings) {
                XCTAssertEqual(configuration[bindingFor: zone], binding)
            }
            XCTAssertEqual(concreteBindings(in: configuration, for: layout), expectedBindings)

            for (zone, binding) in zip(layout.zones, expectedBindings) {
                var mapper = PadMapper(side: .left, configuration: configuration)
                let actions = try mapper.process(touchedSample(in: zone))
                XCTAssertEqual(
                    actions,
                    [.key(try KeyCatalog.resolve(binding), isPressed: true)],
                    "Mapper mismatch for \(zone.rawValue) in \(layout.rawValue)"
                )
            }
        }
    }

    private func concreteBindings(
        in configuration: PadConfiguration,
        for layout: PadZoneLayout
    ) -> [String] {
        switch layout {
        case .radialFour, .fourCorners:
            [
                configuration.dpadKeys.up,
                configuration.dpadKeys.right,
                configuration.dpadKeys.down,
                configuration.dpadKeys.left
            ]
        case .horizontalTwo:
            [configuration.dpadKeys.left, configuration.dpadKeys.right]
        case .verticalTwo:
            [configuration.dpadKeys.up, configuration.dpadKeys.down]
        case .gridNine:
            [
                configuration.gridKeys.topLeft,
                configuration.gridKeys.top,
                configuration.gridKeys.topRight,
                configuration.gridKeys.left,
                configuration.gridKeys.center,
                configuration.gridKeys.right,
                configuration.gridKeys.bottomLeft,
                configuration.gridKeys.bottom,
                configuration.gridKeys.bottomRight
            ]
        }
    }

    private func touchedSample(in zone: ButtonZone) -> TrackpadSample {
        let coordinates: (x: Int16, y: Int16) = switch zone {
        case .topLeft: (-20_000, 20_000)
        case .up: (0, 20_000)
        case .topRight: (20_000, 20_000)
        case .left: (-20_000, 0)
        case .center: (0, 0)
        case .right: (20_000, 0)
        case .bottomLeft: (-20_000, -20_000)
        case .down: (0, -20_000)
        case .bottomRight: (20_000, -20_000)
        }
        return TrackpadSample(
            isTouched: true,
            isClicked: false,
            x: coordinates.x,
            y: coordinates.y,
            pressure: 0,
            timestampNanoseconds: 1
        )
    }

    private func assertDirectionalNavigation(
        from zone: ButtonZone,
        in layout: PadZoneLayout,
        left: ButtonZone,
        right: ButtonZone,
        up: ButtonZone,
        down: ButtonZone,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(moved(zone, .left, layout), left, file: file, line: line)
        XCTAssertEqual(moved(zone, .right, layout), right, file: file, line: line)
        XCTAssertEqual(moved(zone, .up, layout), up, file: file, line: line)
        XCTAssertEqual(moved(zone, .down, layout), down, file: file, line: line)
    }

    private func moved(
        _ zone: ButtonZone,
        _ direction: ZoneNavigationDirection,
        _ layout: PadZoneLayout
    ) -> ButtonZone {
        ZoneSelectionPolicy.moved(from: zone, direction: direction, in: layout)
    }
}
