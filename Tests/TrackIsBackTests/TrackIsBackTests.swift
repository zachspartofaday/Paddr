import XCTest
@testable import TrackIsBackCore

final class TrackIsBackTests: XCTestCase {
    func testTritonParserReadsBothTrackpads() {
        var bytes = [UInt8](repeating: 0, count: 54)
        bytes[0] = 0x42
        writeUInt32(0x0660_0000, to: &bytes, at: 2)
        writeInt16(1_000, to: &bytes, at: 18)
        writeInt16(-2_000, to: &bytes, at: 20)
        writeUInt16(300, to: &bytes, at: 22)
        writeInt16(3_000, to: &bytes, at: 24)
        writeInt16(-4_000, to: &bytes, at: 26)
        writeUInt16(500, to: &bytes, at: 28)

        let pads = TritonParser.parseTrackpads(bytes, timestampNanoseconds: 99)

        XCTAssertEqual(pads?.left, TrackpadSample(isTouched: true, isClicked: true, x: 1_000, y: -2_000, pressure: 300, timestampNanoseconds: 99))
        XCTAssertEqual(pads?.right, TrackpadSample(isTouched: true, isClicked: true, x: 3_000, y: -4_000, pressure: 500, timestampNanoseconds: 99))
    }

    func testDPadZonesResolveCardinalDirections() {
        XCTAssertEqual(PadMapper.activeDirections(x: 0, y: 20_000, deadzone: 0.2), [.up])
        XCTAssertEqual(PadMapper.activeDirections(x: 20_000, y: 0, deadzone: 0.2), [.right])
        XCTAssertEqual(PadMapper.activeDirections(x: 0, y: -20_000, deadzone: 0.2), [.down])
        XCTAssertEqual(PadMapper.activeDirections(x: -20_000, y: 0, deadzone: 0.2), [.left])
        XCTAssertEqual(PadMapper.activeDirections(x: 1_000, y: 1_000, deadzone: 0.2), [])
    }

    func testFourCornerZonesResolveClockwiseBindings() {
        XCTAssertEqual(PadMapper.activeDirections(x: -20_000, y: 20_000, deadzone: 0.1, layout: .fourCorners), [.up])
        XCTAssertEqual(PadMapper.activeDirections(x: 20_000, y: 20_000, deadzone: 0.1, layout: .fourCorners), [.right])
        XCTAssertEqual(PadMapper.activeDirections(x: 20_000, y: -20_000, deadzone: 0.1, layout: .fourCorners), [.down])
        XCTAssertEqual(PadMapper.activeDirections(x: -20_000, y: -20_000, deadzone: 0.1, layout: .fourCorners), [.left])
    }

    func testTwoWayZoneLayouts() {
        XCTAssertEqual(PadMapper.activeDirections(x: -20_000, y: 0, deadzone: 0.1, layout: .horizontalTwo), [.left])
        XCTAssertEqual(PadMapper.activeDirections(x: 20_000, y: 0, deadzone: 0.1, layout: .horizontalTwo), [.right])
        XCTAssertEqual(PadMapper.activeDirections(x: 0, y: 20_000, deadzone: 0.1, layout: .verticalTwo), [.up])
        XCTAssertEqual(PadMapper.activeDirections(x: 0, y: -20_000, deadzone: 0.1, layout: .verticalTwo), [.down])
    }

    func testTwoWayNeutralStripUsesDeadzone() {
        XCTAssertEqual(PadMapper.activeDirections(x: 1_000, y: 20_000, deadzone: 0.1, layout: .horizontalTwo), [])
        XCTAssertEqual(PadMapper.activeDirections(x: 20_000, y: 1_000, deadzone: 0.1, layout: .verticalTwo), [])
    }

    func testNineZoneGridResolvesEveryCell() {
        let coordinates: [(Int16, Int16, ButtonZone)] = [
            (-20_000, 20_000, .topLeft), (0, 20_000, .up), (20_000, 20_000, .topRight),
            (-20_000, 0, .left), (0, 0, .center), (20_000, 0, .right),
            (-20_000, -20_000, .bottomLeft), (0, -20_000, .down), (20_000, -20_000, .bottomRight)
        ]
        for (x, y, expected) in coordinates {
            XCTAssertEqual(
                PadMapper.activeButtonZones(x: x, y: y, deadzone: 0.2, layout: .gridNine),
                [expected]
            )
        }
    }

    func testNineZoneGridUsesIndependentKeyAssignments() throws {
        var mapper = PadMapper(
            side: .left,
            configuration: PadConfiguration(mode: .dpad, zoneLayout: .gridNine)
        )
        let centerDown = try mapper.process(sample(touched: true, time: 1))
        let topRight = try mapper.process(sample(touched: true, x: 20_000, y: 20_000, time: 2))

        XCTAssertEqual(centerDown, [.key(try KeyCatalog.resolve("space"), isPressed: true)])
        XCTAssertEqual(topRight, [
            .key(try KeyCatalog.resolve("space"), isPressed: false),
            .key(try KeyCatalog.resolve("e"), isPressed: true)
        ])
    }

    func testDPadHoldsAndReleasesConfiguredKeys() throws {
        var mapper = PadMapper(
            side: .left,
            configuration: PadConfiguration(mode: .dpad, dpadKeys: .wasd)
        )
        let down = try mapper.process(sample(touched: true, x: 0, y: 20_000, time: 1))
        let across = try mapper.process(sample(touched: true, x: 20_000, y: 0, time: 2))
        let lift = try mapper.process(sample(touched: false, time: 3))

        XCTAssertEqual(down, [.key(try KeyCatalog.resolve("w"), isPressed: true)])
        XCTAssertEqual(across, [
            .key(try KeyCatalog.resolve("w"), isPressed: false),
            .key(try KeyCatalog.resolve("d"), isPressed: true)
        ])
        XCTAssertEqual(lift, [.key(try KeyCatalog.resolve("d"), isPressed: false)])
    }

    func testButtonZoneCanHoldAndReleaseMouseButton() throws {
        let bindings = DirectionKeyConfiguration(
            up: TapBindingCatalog.leftMouseButton,
            right: "right",
            down: "down",
            left: "left"
        )
        var mapper = PadMapper(
            side: .left,
            configuration: PadConfiguration(mode: .dpad, dpadKeys: bindings)
        )

        let press = try mapper.process(sample(touched: true, x: 0, y: 20_000, time: 1))
        let release = try mapper.process(sample(touched: false, time: 2))

        XCTAssertEqual(press, [.mouseButton(.left, isPressed: true)])
        XCTAssertEqual(release, [.mouseButton(.left, isPressed: false)])
    }

    func testNineZoneMouseButtonReleasesWhenCrossingCells() throws {
        var grid = GridKeyConfiguration.keyboard
        grid.center = TapBindingCatalog.rightMouseButton
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .dpad, zoneLayout: .gridNine, gridKeys: grid)
        )

        let center = try mapper.process(sample(touched: true, time: 1))
        let moveRight = try mapper.process(sample(touched: true, x: 20_000, time: 2))

        XCTAssertEqual(center, [.mouseButton(.right, isPressed: true)])
        XCTAssertEqual(moveRight, [
            .mouseButton(.right, isPressed: false),
            .key(try KeyCatalog.resolve("d"), isPressed: true)
        ])
    }

    func testConfigurationAcceptsMouseButtonsForZoneActions() throws {
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = TapBindingCatalog.leftMouseButton
        configuration.left.zoneLayout = .gridNine
        configuration.left.gridKeys.center = TapBindingCatalog.rightMouseButton

        let validated = try configuration.validated()

        XCTAssertEqual(validated.left.dpadKeys.up, TapBindingCatalog.leftMouseButton)
        XCTAssertEqual(validated.left.gridKeys.center, TapBindingCatalog.rightMouseButton)
    }

    func testCenterTouchTapEmitsConfiguredKey() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, tapKey: "space")
        )
        _ = try mapper.process(sample(touched: true, x: 100, y: 100, time: 1_000_000))
        let actions = try mapper.process(sample(touched: false, x: 150, y: 100, time: 101_000_000))
        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(actions, [.key(space, isPressed: true), .key(space, isPressed: false)])
    }

    func testTouchTapCanClickEitherMouseButton() throws {
        for (binding, button) in [
            (TapBindingCatalog.leftMouseButton, MouseButtonBinding.left),
            (TapBindingCatalog.rightMouseButton, MouseButtonBinding.right)
        ] {
            var mapper = PadMapper(
                side: .right,
                configuration: PadConfiguration(mode: .mouse, tapKey: binding)
            )
            _ = try mapper.process(sample(touched: true, time: 1_000_000))
            let actions = try mapper.process(sample(touched: false, time: 20_000_000))
            XCTAssertEqual(actions, [
                .mouseButton(button, isPressed: true),
                .mouseButton(button, isPressed: false)
            ])
        }
    }

    func testMouseCenterTapZoneSuppressesMovementAndAllowsTap() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, mouseDeadzone: 0.2, tapKey: "space")
        )
        _ = try mapper.process(sample(touched: true, x: 0, y: 0, time: 1_000_000))
        XCTAssertTrue(try mapper.process(sample(touched: true, x: 2_000, y: 1_000, time: 10_000_000)).isEmpty)
        let actions = try mapper.process(sample(touched: false, x: 2_000, y: 1_000, time: 20_000_000))
        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(actions, [.key(space, isPressed: true), .key(space, isPressed: false)])
    }

    func testFullMouseCenterTapRadiusIncludesPadEdge() throws {
        let configuration = PadConfiguration(mode: .mouse, mouseDeadzone: 1, tapKey: "space")
        var mapper = PadMapper(side: .right, configuration: configuration)

        XCTAssertNoThrow(try TrackIsBackConfiguration(left: .init(mode: .disabled), right: configuration).validated())
        XCTAssertTrue(try mapper.process(sample(touched: true, x: .max, y: 0, time: 1_000_000)).isEmpty)

        let actions = try mapper.process(sample(touched: false, x: .max, y: 0, time: 20_000_000))
        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(actions, [.key(space, isPressed: true), .key(space, isPressed: false)])
    }

    func testLeavingMouseCenterTapZoneDoesNotJumpCursor() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, mouseDeadzone: 0.2, tapKey: "space")
        )
        _ = try mapper.process(sample(touched: true, x: 0, y: 0, time: 1))
        XCTAssertTrue(try mapper.process(sample(touched: true, x: 10_000, y: 0, time: 2)).isEmpty)
        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 10_700, y: 0, time: 3)),
            [.mouseMove(dx: 1, dy: 0)]
        )
        XCTAssertTrue(try mapper.process(sample(touched: false, x: 10_700, y: 0, time: 4)).isEmpty)
    }

    func testMovedTouchDoesNotTap() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, tapKey: "space", tapMaximumMovement: 100)
        )
        _ = try mapper.process(sample(touched: true, x: 0, y: 0, time: 1_000_000))
        _ = try mapper.process(sample(touched: true, x: 1_000, y: 0, time: 20_000_000))
        let actions = try mapper.process(sample(touched: false, x: 1_000, y: 0, time: 40_000_000))
        XCTAssertTrue(actions.isEmpty)
    }

    func testMouseSensitivityScalesMovement() throws {
        var mapper = PadMapper(side: .right, configuration: PadConfiguration(mode: .mouse, sensitivity: 2))
        _ = try mapper.process(sample(touched: true, x: 0, y: 0, time: 1))
        let actions = try mapper.process(sample(touched: true, x: 700, y: 350, time: 2))
        XCTAssertEqual(actions, [.mouseMove(dx: 2, dy: -1)])
    }

    private func sample(touched: Bool, x: Int16 = 0, y: Int16 = 0, time: UInt64) -> TrackpadSample {
        TrackpadSample(isTouched: touched, isClicked: false, x: x, y: y, pressure: 0, timestampNanoseconds: time)
    }

    private func writeUInt16(_ value: UInt16, to bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func writeInt16(_ value: Int16, to bytes: inout [UInt8], at offset: Int) {
        writeUInt16(UInt16(bitPattern: value), to: &bytes, at: offset)
    }

    private func writeUInt32(_ value: UInt32, to bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
