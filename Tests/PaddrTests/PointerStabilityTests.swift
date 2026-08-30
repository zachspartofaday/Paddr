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
            positions: [70, 140, 210, 280, 350, 420],
            intervalNanoseconds: 4_000_000
        )
        let fastDistance = try totalPointerDistance(
            configuration: configuration,
            positions: [7_000, 14_000, 21_000, 28_000, 32_000, 32_767],
            intervalNanoseconds: 4_000_000
        )

        XCTAssertGreaterThan(slowDistance, 0)
        XCTAssertGreaterThan(fastDistance / (32_767.0 / 700), slowDistance / 0.6)
    }

    func testSustainedSlowPointerMotionCrossesRetainedNoiseGateByTwentyFourMilliseconds() throws {
        let configuration = PadConfiguration(
            mode: .mouse,
            pointerSmoothingEnabled: true,
            pointerSmoothingStrength: 1
        )
        var mapper = PadMapper(side: .right, configuration: configuration)

        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        for report in 1...5 {
            XCTAssertTrue(
                try mapper.process(
                    sample(
                        touched: true,
                        x: Int16(report * 70),
                        time: 1_000_000 + UInt64(report) * 4_000_000
                    )
                ).isEmpty,
                "Report \(report) should remain below the retained 0.05-point noise gate"
            )
        }

        let actions = try mapper.process(
            sample(touched: true, x: 420, time: 25_000_000)
        )
        let move = try mouseMove(in: actions)
        XCTAssertGreaterThanOrEqual(move.dx, 0.05)
        XCTAssertEqual(move.dy, 0, accuracy: 0.000_000_000_001)
    }

    func testSmoothedResidualsIncludeBothAxesAndCancelSignedReversals() throws {
        let configuration = PadConfiguration(
            mode: .mouse,
            pointerSmoothingEnabled: true,
            pointerSmoothingStrength: 1
        )
        var bothAxes = PadMapper(side: .right, configuration: configuration)
        _ = try bothAxes.process(sample(touched: true, time: 1_000_000))
        var bothAxesActions: [TrackpadOutputAction] = []
        for report in 1...6 {
            bothAxesActions += try bothAxes.process(
                sample(
                    touched: true,
                    x: Int16(report * 70),
                    y: Int16(report * 35),
                    time: 1_000_000 + UInt64(report) * 4_000_000
                )
            )
        }
        let bothAxesMove = try mouseMove(in: bothAxesActions)
        XCTAssertGreaterThan(bothAxesMove.dx, 0)
        XCTAssertLessThan(bothAxesMove.dy, 0)

        var reversing = PadMapper(side: .right, configuration: configuration)
        _ = try reversing.process(sample(touched: true, time: 1_000_000))
        let yPositions: [Int16] = [70, 140, 210, 140, 70, 0, -70, -140, -210]
        var reversalActions: [TrackpadOutputAction] = []
        for (index, y) in yPositions.enumerated() {
            reversalActions += try reversing.process(
                sample(
                    touched: true,
                    x: Int16((index + 1) * 35),
                    y: y,
                    time: 5_000_000 + UInt64(index) * 4_000_000
                )
            )
        }
        let reversalMove = try mouseMove(in: reversalActions)
        XCTAssertGreaterThanOrEqual(reversalMove.dx, 0.05)
        XCTAssertLessThan(
            abs(reversalMove.dy),
            0.01,
            "Signed Y residuals should cancel instead of accumulating absolute distance"
        )
    }

    func testPendingSmoothedMotionResetsAcrossLiftReleaseAllAndLongReportGaps() throws {
        let configuration = PadConfiguration(
            mode: .mouse,
            pointerSmoothingEnabled: true,
            pointerSmoothingStrength: 1
        )

        var afterLift = try mapperWithPendingSlowMotion(configuration: configuration)
        XCTAssertTrue(
            try afterLift.process(sample(touched: false, x: 350, time: 22_000_000)).isEmpty
        )
        XCTAssertTrue(
            try afterLift.process(sample(touched: true, x: 10_000, time: 23_000_000)).isEmpty
        )
        XCTAssertTrue(
            try afterLift.process(sample(touched: true, x: 10_070, time: 27_000_000)).isEmpty
        )

        var afterReleaseAll = try mapperWithPendingSlowMotion(configuration: configuration)
        XCTAssertTrue(try afterReleaseAll.releaseAll().isEmpty)
        XCTAssertTrue(
            try afterReleaseAll.process(sample(touched: true, x: 20_000, time: 23_000_000)).isEmpty
        )
        XCTAssertTrue(
            try afterReleaseAll.process(sample(touched: true, x: 20_070, time: 27_000_000)).isEmpty
        )

        var afterLongGap = try mapperWithPendingSlowMotion(configuration: configuration)
        XCTAssertTrue(
            try afterLongGap.process(sample(touched: true, x: 350, time: 122_000_000)).isEmpty
        )
        XCTAssertTrue(
            try afterLongGap.process(sample(touched: true, x: 420, time: 126_000_000)).isEmpty
        )
    }

    func testSmoothingDisabledAndZeroStrengthPreservePerReportMotionExactly() throws {
        let samples = [
            sample(touched: true, time: 1_000_000),
            sample(touched: true, x: 700, y: 350, time: 5_000_000),
            sample(touched: true, x: 770, y: 385, time: 9_000_000),
            sample(touched: true, x: 1_470, y: -315, time: 13_000_000),
            sample(touched: false, x: 1_470, y: -315, time: 17_000_000)
        ]
        let disabled = try actions(
            for: samples,
            configuration: PadConfiguration(
                mode: .mouse,
                pointerSmoothingEnabled: false,
                pointerSmoothingStrength: 1
            )
        )
        let zeroStrength = try actions(
            for: samples,
            configuration: PadConfiguration(
                mode: .mouse,
                pointerSmoothingEnabled: true,
                pointerSmoothingStrength: 0
            )
        )

        XCTAssertEqual(disabled, zeroStrength)
        XCTAssertEqual(
            disabled,
            [
                .mouseMove(dx: 1, dy: -0.5),
                .mouseMove(dx: 0.1, dy: -0.05),
                .mouseMove(dx: 1, dy: 1)
            ]
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

    private func mapperWithPendingSlowMotion(
        configuration: PadConfiguration
    ) throws -> PadMapper {
        var mapper = PadMapper(side: .right, configuration: configuration)
        _ = try mapper.process(sample(touched: true, time: 1_000_000))
        for report in 1...5 {
            XCTAssertTrue(
                try mapper.process(
                    sample(
                        touched: true,
                        x: Int16(report * 70),
                        time: 1_000_000 + UInt64(report) * 4_000_000
                    )
                ).isEmpty
            )
        }
        return mapper
    }

    private func actions(
        for samples: [TrackpadSample],
        configuration: PadConfiguration
    ) throws -> [TrackpadOutputAction] {
        var mapper = PadMapper(side: .right, configuration: configuration)
        return try samples.flatMap { try mapper.process($0) }
    }

    private func mouseMove(
        in actions: [TrackpadOutputAction]
    ) throws -> (dx: Double, dy: Double) {
        guard case let .mouseMove(dx, dy)? = actions.first else {
            XCTFail("Expected a mouse move action")
            return (0, 0)
        }
        return (dx, dy)
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
