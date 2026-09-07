import XCTest
@testable import PaddrCore

final class ScrollConservationTests: XCTestCase {
    func testSignedTotalsAreIndependentOfReportSegmentation() throws {
        for direction in [1, -1] {
            let fine = try gesture(points: (0...10).map { direction * $0 * 120 })
            let coarse = try gesture(points: [0, direction * 1200])
            XCTAssertEqual(total(fine).0, Double(direction * 2))
            XCTAssertEqual(total(fine).1, Double(-direction * 2))
            XCTAssertEqual(total(fine).0, total(coarse).0)
            XCTAssertEqual(total(fine).1, total(coarse).1)
        }
    }

    func testSubThresholdSamplesAccumulateAndReversalCancelsSignedResidual() throws {
        XCTAssertEqual(total(try gesture(points: Array(stride(from: 0, through: 960, by: 24)))).0, 2)
        var mapper = PadMapper(side: .left, configuration: .init(mode: .scroll, scrollSensitivity: 0.5))
        for x in [0, 360, 0, -360] { XCTAssertTrue(try mapper.process(sample(x)).isEmpty) }
        XCTAssertEqual(try mapper.process(sample(-480)), [.scroll(dx: -1, dy: 1)])
    }

    func testAxesPadsZeroSensitivityAndTouchOrReleaseReset() throws {
        var left = PadMapper(side: .left, configuration: .init(mode: .scroll, scrollSensitivity: 0.5))
        var right = PadMapper(side: .right, configuration: .init(mode: .scroll, scrollSensitivity: 0.5))
        _ = try left.process(sample(0))
        _ = try right.process(sample(0))
        XCTAssertTrue(try left.process(sample(360, y: 0)).isEmpty)
        XCTAssertTrue(try right.process(sample(120, y: 0)).isEmpty)
        XCTAssertEqual(try left.process(sample(480, y: 0)), [.scroll(dx: 1, dy: 0)])
        XCTAssertTrue(try right.process(sample(240, y: 0)).isEmpty)
        XCTAssertEqual(try left.process(sample(480, y: 480)), [.scroll(dx: 0, dy: -1)])
        for releaseAll in [false, true] {
            var mapper = PadMapper(side: .left, configuration: .init(mode: .scroll, scrollSensitivity: 0.5))
            _ = try mapper.process(sample(0))
            _ = try mapper.process(sample(360))
            if releaseAll { _ = try mapper.releaseAll() } else { _ = try mapper.process(sample(360, touched: false)) }
            _ = try mapper.process(sample(0))
            XCTAssertTrue(try mapper.process(sample(120)).isEmpty)
            XCTAssertEqual(try mapper.process(sample(480)), [.scroll(dx: 1, dy: -1)])
        }
        XCTAssertTrue(try gesture(points: [0, 10000, -10000], sensitivity: 0).isEmpty)
    }

    private func gesture(points: [Int], sensitivity: Double = 0.5) throws -> [TrackpadOutputAction] {
        var mapper = PadMapper(side: .left, configuration: .init(mode: .scroll, scrollSensitivity: sensitivity))
        return try points.flatMap { try mapper.process(sample($0)) }
    }

    private func sample(_ x: Int, y: Int? = nil, touched: Bool = true) -> TrackpadSample {
        .init(isTouched: touched, isClicked: false, x: Int16(x), y: Int16(y ?? x), pressure: 0, timestampNanoseconds: 0)
    }

    private func total(_ actions: [TrackpadOutputAction]) -> (Double, Double) {
        actions.reduce((0, 0)) { sum, action in
            guard case let .scroll(dx, dy) = action else { return sum }
            return (sum.0 + dx, sum.1 + dy)
        }
    }
}
