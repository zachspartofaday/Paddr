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

    func testTritonParserAcceptsUnpadded46ByteStateReports() {
        var noQuat = [UInt8](repeating: 0, count: 46)
        noQuat[0] = 0x42
        writeUInt32(0x0200_0000, to: &noQuat, at: 2)
        writeInt16(1_000, to: &noQuat, at: 18)
        let noQuatPads = TritonParser.parseTrackpads(noQuat, timestampNanoseconds: 7)
        XCTAssertEqual(noQuatPads?.left.isTouched, true)
        XCTAssertEqual(noQuatPads?.left.x, 1_000)

        var timestamped = [UInt8](repeating: 0, count: 46)
        timestamped[0] = 0x47
        writeUInt32(0x0020_0000, to: &timestamped, at: 2)
        writeInt16(2_000, to: &timestamped, at: 26)
        let timestampedPads = TritonParser.parseTrackpads(timestamped, timestampNanoseconds: 7)
        XCTAssertEqual(timestampedPads?.right.isTouched, true)
        XCTAssertEqual(timestampedPads?.right.x, 2_000)
    }

    func testTritonParserReadsWirelessStatusReports() {
        XCTAssertEqual(TritonParser.parseWirelessConnection([0x46, 2]), true)
        XCTAssertEqual(TritonParser.parseWirelessConnection([0x79, 2]), true)
        XCTAssertEqual(TritonParser.parseWirelessConnection([0x46, 1]), false)
        XCTAssertEqual(TritonParser.parseWirelessConnection([0x79, 1]), false)
        XCTAssertEqual(TritonParser.parseWirelessConnection([0x46, 2, 0, 0]), true)
        XCTAssertNil(TritonParser.parseWirelessConnection([]))
        XCTAssertNil(TritonParser.parseWirelessConnection([0x46]))
        XCTAssertNil(TritonParser.parseWirelessConnection([0x46, 0]))
        XCTAssertNil(TritonParser.parseWirelessConnection([0x46, 3]))
        XCTAssertNil(TritonParser.parseWirelessConnection([0x42, 2]))
    }

    func testControllerInterfaceFilterMatchesDongleSlots() {
        XCTAssertTrue(TritonHIDDevice.isControllerInterface(interfaceNumber: 2, maximumInputReportSize: 54))
        XCTAssertTrue(TritonHIDDevice.isControllerInterface(interfaceNumber: 3, maximumInputReportSize: 64))
        XCTAssertTrue(TritonHIDDevice.isControllerInterface(interfaceNumber: 5, maximumInputReportSize: 46))
        XCTAssertFalse(TritonHIDDevice.isControllerInterface(interfaceNumber: 0, maximumInputReportSize: 54))
        XCTAssertFalse(TritonHIDDevice.isControllerInterface(interfaceNumber: 1, maximumInputReportSize: 54))
        XCTAssertFalse(TritonHIDDevice.isControllerInterface(interfaceNumber: 6, maximumInputReportSize: 54))
        XCTAssertTrue(TritonHIDDevice.isControllerInterface(interfaceNumber: nil, maximumInputReportSize: 30))
        XCTAssertFalse(TritonHIDDevice.isControllerInterface(interfaceNumber: nil, maximumInputReportSize: 8))
    }

    func testDeviceSummaryDescriptionListsAllInterfaces() {
        let summary = TritonDeviceSummary(
            productID: 0x1304,
            interfaces: [
                TritonInterfaceSummary(interfaceNumber: 2, usagePage: 1, usage: 2, maximumInputReportSize: 54),
                TritonInterfaceSummary(interfaceNumber: 3, usagePage: nil, usage: nil, maximumInputReportSize: 54),
                TritonInterfaceSummary(interfaceNumber: nil, usagePage: nil, usage: nil, maximumInputReportSize: 46)
            ]
        )
        XCTAssertEqual(summary.description, "Valve 0x28DE:0x1304 interfaces=2,3,? inputReport=46,54")
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

    func testConfigurationAcceptsIndependentZoneModesForBothPads() throws {
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.zoneLayout = .horizontalTwo
        configuration.left.dpadKeys.left = "Q"
        configuration.right.mode = .dpad
        configuration.right.zoneLayout = .verticalTwo
        configuration.right.dpadKeys.up = "E"

        let validated = try configuration.validated()

        XCTAssertEqual(validated.left.mode, .dpad)
        XCTAssertEqual(validated.left.zoneLayout, .horizontalTwo)
        XCTAssertEqual(validated.left.dpadKeys.left, "q")
        XCTAssertEqual(validated.right.mode, .dpad)
        XCTAssertEqual(validated.right.zoneLayout, .verticalTwo)
        XCTAssertEqual(validated.right.dpadKeys.up, "e")
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

    func testMouseUsesPointerSensitivityInsteadOfScrollSensitivity() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, sensitivity: 2, scrollSensitivity: 0.1)
        )
        _ = try mapper.process(sample(touched: true, x: 0, y: 0, time: 1))

        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 700, y: 350, time: 2)),
            [.mouseMove(dx: 2, dy: -1)]
        )
    }

    func testScrollUsesScrollSensitivityInsteadOfPointerSensitivity() throws {
        var mapper = PadMapper(
            side: .left,
            configuration: PadConfiguration(mode: .scroll, sensitivity: 20, scrollSensitivity: 0.5)
        )
        _ = try mapper.process(sample(touched: true, x: 0, y: 0, time: 1))

        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 240, y: 120, time: 2)),
            [.scroll(dx: 0.5, dy: -0.25)]
        )
    }

    func testZeroMouseAccelerationPreservesLegacyMouseActionsExactly() throws {
        let configuration = PadConfiguration(mode: .mouse, mouseAcceleration: 0)

        var positive = PadMapper(side: .right, configuration: configuration)
        _ = try positive.process(sample(touched: true, time: 10))
        XCTAssertEqual(
            try positive.process(sample(touched: true, x: 700, y: 350, time: 20)),
            [.mouseMove(dx: 1, dy: -0.5)]
        )

        var negative = PadMapper(side: .right, configuration: configuration)
        _ = try negative.process(sample(touched: true, time: 20))
        XCTAssertEqual(
            try negative.process(sample(touched: true, x: -700, y: -350, time: 10)),
            [.mouseMove(dx: -1, dy: 0.5)]
        )

        var diagonal = PadMapper(side: .right, configuration: configuration)
        _ = try diagonal.process(sample(touched: true, x: -700, y: 700, time: 1))
        XCTAssertEqual(
            try diagonal.process(sample(touched: true, x: 700, y: -700, time: 2)),
            [.mouseMove(dx: 2, dy: 2)]
        )

        var subthreshold = PadMapper(side: .right, configuration: configuration)
        _ = try subthreshold.process(sample(touched: true, time: 1))
        XCTAssertTrue(
            try subthreshold.process(sample(touched: true, x: 34, y: -34, time: 2)).isEmpty
        )

        var deadzoneAndLift = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, mouseAcceleration: 0, mouseDeadzone: 0.2)
        )
        _ = try deadzoneAndLift.process(sample(touched: true, time: 1))
        XCTAssertTrue(
            try deadzoneAndLift.process(sample(touched: true, x: 10_000, time: 2)).isEmpty
        )
        XCTAssertEqual(
            try deadzoneAndLift.process(sample(touched: true, x: 10_700, time: 3)),
            [.mouseMove(dx: 1, dy: 0)]
        )
        XCTAssertTrue(try deadzoneAndLift.process(sample(touched: false, x: 10_700, time: 4)).isEmpty)
        XCTAssertTrue(try deadzoneAndLift.process(sample(touched: true, x: -10_000, time: 5)).isEmpty)
        XCTAssertEqual(
            try deadzoneAndLift.process(sample(touched: true, x: -10_700, time: 6)),
            [.mouseMove(dx: -1, dy: 0)]
        )
    }

    func testFasterEqualMouseDisplacementReceivesMoreAcceleration() throws {
        let slow = try mouseMove(deltaX: 700, interval: 50_000_000, acceleration: 1)
        let fast = try mouseMove(deltaX: 700, interval: 5_000_000, acceleration: 1)

        XCTAssertEqual(slow.dx, 1)
        XCTAssertGreaterThan(fast.dx, slow.dx)
    }

    func testMouseAccelerationSettingIsMonotonicAndCappedAtFourTimesLinear() throws {
        let linear = try mouseMove(deltaX: 700, interval: 1_000_000, acceleration: 0)
        let quarter = try mouseMove(deltaX: 700, interval: 1_000_000, acceleration: 0.25)
        let half = try mouseMove(deltaX: 700, interval: 1_000_000, acceleration: 0.5)
        let full = try mouseMove(deltaX: 700, interval: 1_000_000, acceleration: 1)

        XCTAssertLessThan(linear.dx, quarter.dx)
        XCTAssertLessThan(quarter.dx, half.dx)
        XCTAssertLessThan(half.dx, full.dx)
        XCTAssertEqual(full.dx, linear.dx * 4)
    }

    func testEquivalentUnscaledMouseSpeedsReceiveEquivalentGain() throws {
        let short = try mouseMove(deltaX: 700, interval: 10_000_000, acceleration: 0.8)
        let long = try mouseMove(deltaX: 1_400, interval: 20_000_000, acceleration: 0.8)

        XCTAssertEqual(long.dx, short.dx * 2, accuracy: 0.000_000_1)
    }

    func testNonMonotonicAndStaleMouseTimestampsUseLinearGain() throws {
        let equal = try mouseMove(start: 200_000_000, end: 200_000_000, acceleration: 1)
        let reversed = try mouseMove(start: 200_000_000, end: 100_000_000, acceleration: 1)
        let stale = try mouseMove(start: 200_000_000, end: 301_000_000, acceleration: 1)

        XCTAssertEqual(equal.dx, 1)
        XCTAssertEqual(reversed.dx, 1)
        XCTAssertEqual(stale.dx, 1)
    }

    func testMouseAccelerationRestartsAfterLiftWithoutAJump() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, mouseAcceleration: 1)
        )
        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 700, time: 2_000_000)),
            [.mouseMove(dx: 4, dy: 0)]
        )
        XCTAssertTrue(try mapper.process(sample(touched: false, x: 700, time: 3_000_000)).isEmpty)
        XCTAssertTrue(try mapper.process(sample(touched: true, x: 20_000, time: 4_000_000)).isEmpty)
        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 20_700, time: 5_000_000)),
            [.mouseMove(dx: 4, dy: 0)]
        )
    }

    func testMouseAccelerationDoesNotAffectScrollTapOrZones() throws {
        var scroll = PadMapper(
            side: .left,
            configuration: PadConfiguration(mode: .scroll, scrollSensitivity: 0.5, mouseAcceleration: 1)
        )
        _ = try scroll.process(sample(touched: true, time: 1))
        XCTAssertEqual(
            try scroll.process(sample(touched: true, x: 240, y: 120, time: 2)),
            [.scroll(dx: 0.5, dy: -0.25)]
        )

        var tap = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, mouseAcceleration: 1, tapKey: "space")
        )
        _ = try tap.process(sample(touched: true, time: 1_000_000))
        XCTAssertEqual(
            try tap.process(sample(touched: false, time: 20_000_000)),
            [
                .key(try KeyCatalog.resolve("space"), isPressed: true),
                .key(try KeyCatalog.resolve("space"), isPressed: false)
            ]
        )

        var zones = PadMapper(
            side: .left,
            configuration: PadConfiguration(mode: .dpad, mouseAcceleration: 1, dpadKeys: .wasd)
        )
        XCTAssertEqual(
            try zones.process(sample(touched: true, y: 20_000, time: 1)),
            [.key(try KeyCatalog.resolve("w"), isPressed: true)]
        )
    }

    private func mouseMove(
        deltaX: Int16 = 700,
        interval: UInt64 = 1_000_000,
        start: UInt64 = 100_000_000,
        end: UInt64? = nil,
        acceleration: Double
    ) throws -> (dx: Double, dy: Double) {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(mode: .mouse, mouseAcceleration: acceleration)
        )
        _ = try mapper.process(sample(touched: true, time: start))
        let actions = try mapper.process(
            sample(touched: true, x: deltaX, time: end ?? start + interval)
        )
        guard case let .mouseMove(dx, dy)? = actions.first else {
            XCTFail("Expected a mouse movement action")
            return (0, 0)
        }
        return (dx, dy)
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
