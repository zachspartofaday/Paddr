import XCTest
@testable import PaddrCore

final class PointerStabilityTests: XCTestCase {
    func testTapStabilizationDiscardsLiftJitterBeforeClick() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(
                mode: .mouse,
                sensitivity: 2,
                tapKey: TapBindingCatalog.leftMouseButton,
                tapStabilizationThresholdPoints: 6
            )
        )

        XCTAssertTrue(try mapper.process(sample(touched: true, time: 1_000_000)).isEmpty)
        XCTAssertTrue(
            try mapper.process(sample(touched: true, x: 2_000, time: 20_000_000)).isEmpty
        )
        XCTAssertEqual(
            try mapper.process(sample(touched: false, x: 2_000, time: 40_000_000)),
            [
                .mouseButton(.left, isPressed: true),
                .mouseButton(.left, isPressed: false)
            ]
        )
    }

    func testCrossingTapToleranceCancelsTapAndResumesWithoutCatchUpJump() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(
                mode: .mouse,
                tapKey: TapBindingCatalog.leftMouseButton,
                tapStabilizationThresholdPoints: 6
            )
        )

        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        XCTAssertTrue(
            try mapper.process(sample(touched: true, x: 4_900, time: 20_000_000)).isEmpty,
            "The threshold-crossing report should become the new pointer anchor"
        )
        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 5_600, time: 24_000_000)),
            [.mouseMove(dx: 1, dy: 0)]
        )
        XCTAssertTrue(
            try mapper.process(sample(touched: false, x: 5_600, time: 40_000_000)).isEmpty
        )
    }

    func testTapTimeoutCancelsStabilizationAndReanchorsPointer() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(
                mode: .mouse,
                tapKey: "space",
                tapMaximumMilliseconds: 250
            )
        )

        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        XCTAssertTrue(
            try mapper.process(sample(touched: true, time: 252_000_000)).isEmpty
        )
        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 700, time: 256_000_000)),
            [.mouseMove(dx: 1, dy: 0)]
        )
        XCTAssertTrue(
            try mapper.process(sample(touched: false, x: 700, time: 260_000_000)).isEmpty
        )
    }

    func testDisabledTapStabilizationPreservesLegacyMoveThenTapBehavior() throws {
        var mapper = PadMapper(
            side: .right,
            configuration: PadConfiguration(
                mode: .mouse,
                tapKey: "space",
                tapStabilizationEnabled: false
            )
        )

        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        XCTAssertEqual(
            try mapper.process(sample(touched: true, x: 700, time: 20_000_000)),
            [.mouseMove(dx: 1, dy: 0)]
        )
        XCTAssertEqual(
            try mapper.process(sample(touched: false, x: 700, time: 40_000_000)),
            [
                .key(try KeyCatalog.resolve("space"), isPressed: true),
                .key(try KeyCatalog.resolve("space"), isPressed: false)
            ]
        )
    }

    func testPointerSmoothingReducesAlternatingLowSpeedJitter() throws {
        let rawDistance = try totalPointerDistance(
            configuration: PadConfiguration(mode: .mouse),
            positions: [700, 0, 700, 0],
            intervalNanoseconds: 20_000_000
        )
        let smoothedDistance = try totalPointerDistance(
            configuration: PadConfiguration(
                mode: .mouse,
                pointerSmoothingEnabled: true,
                pointerSmoothingStrength: 1
            ),
            positions: [700, 0, 700, 0],
            intervalNanoseconds: 20_000_000
        )

        XCTAssertEqual(rawDistance, 4, accuracy: 0.000_001)
        XCTAssertGreaterThan(smoothedDistance, 0)
        XCTAssertLessThan(smoothedDistance, rawDistance)
    }

    func testAdaptiveSmoothingAttenuatesFastMotionLessThanSlowMotion() throws {
        let configuration = PadConfiguration(
            mode: .mouse,
            pointerSmoothingEnabled: true,
            pointerSmoothingStrength: 1
        )
        let slowDistance = try totalPointerDistance(
            configuration: configuration,
            positions: [70, 140, 210, 280],
            intervalNanoseconds: 4_000_000
        )
        let fastDistance = try totalPointerDistance(
            configuration: configuration,
            positions: [7_000, 14_000, 21_000, 28_000],
            intervalNanoseconds: 4_000_000
        )

        XCTAssertGreaterThan(fastDistance / 40, slowDistance / 0.4)
    }

    func testPointerFilterResetsAcrossLiftAndReleaseAll() throws {
        let configuration = PadConfiguration(
            mode: .mouse,
            pointerSmoothingEnabled: true,
            pointerSmoothingStrength: 0.5
        )
        var mapper = PadMapper(side: .right, configuration: configuration)

        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        let firstMove = try mapper.process(sample(touched: true, x: 700, time: 5_000_000))
        _ = try mapper.process(sample(touched: false, x: 700, time: 6_000_000))
        _ = try mapper.process(sample(touched: true, x: 20_000, time: 7_000_000))
        let afterLift = try mapper.process(sample(touched: true, x: 20_700, time: 11_000_000))

        XCTAssertEqual(try mouseDX(in: afterLift), try mouseDX(in: firstMove), accuracy: 0.000_000_000_001)
        XCTAssertTrue(try mapper.releaseAll().isEmpty)
        _ = try mapper.process(sample(touched: true, x: -20_000, time: 12_000_000))
        let afterReleaseAll = try mapper.process(
            sample(touched: true, x: -19_300, time: 16_000_000)
        )
        XCTAssertEqual(
            try mouseDX(in: afterReleaseAll),
            try mouseDX(in: firstMove),
            accuracy: 0.000_000_000_001
        )
    }

    private func totalPointerDistance(
        configuration: PadConfiguration,
        positions: [Int16],
        intervalNanoseconds: UInt64
    ) throws -> Double {
        var mapper = PadMapper(side: .right, configuration: configuration)
        var timestamp: UInt64 = 1_000_000
        _ = try mapper.process(sample(touched: true, time: timestamp))
        var distance = 0.0
        for position in positions {
            timestamp += intervalNanoseconds
            for action in try mapper.process(
                sample(touched: true, x: position, time: timestamp)
            ) {
                guard case let .mouseMove(dx, dy) = action else { continue }
                distance += hypot(dx, dy)
            }
        }
        return distance
    }

    private func mouseDX(in actions: [TrackpadOutputAction]) throws -> Double {
        guard case let .mouseMove(dx, _)? = actions.first else {
            XCTFail("Expected a mouse move action")
            return 0
        }
        return dx
    }

    private func sample(
        touched: Bool,
        x: Int16 = 0,
        y: Int16 = 0,
        time: UInt64
    ) -> TrackpadSample {
        TrackpadSample(
            isTouched: touched,
            isClicked: false,
            x: x,
            y: y,
            pressure: 0,
            timestampNanoseconds: time
        )
    }
}
