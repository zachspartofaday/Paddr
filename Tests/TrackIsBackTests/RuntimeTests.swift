import Foundation
import Synchronization
import XCTest
@testable import TrackIsBackCore

final class RuntimeTests: XCTestCase {
    func testBothPadsEmitDistinctZoneBindingsAndReleaseIndependently() throws {
        let output = RecordingOutput()
        let hid = ScriptedTrackpadHID(reports: [
            .init(left: (true, 0, 20_000), right: (true, 0, 20_000)),
            .init(left: (false, 0, 20_000), right: (true, 0, 20_000)),
            .init(left: (false, 0, 20_000), right: (false, 0, 20_000))
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "return"

        let result = try run(configuration: configuration, hid: hid, output: output)

        let space = try KeyCatalog.resolve("space")
        let returnKey = try KeyCatalog.resolve("return")
        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 3, actionCount: 4))
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(returnKey, isPressed: true),
            .key(space, isPressed: false),
            .key(returnKey, isPressed: false)
        ])
    }

    func testSharedZoneBindingSurvivesCrossingAndOtherPadLiftUntilLastOwnerLifts() throws {
        let output = RecordingOutput()
        let hid = ScriptedTrackpadHID(reports: [
            .init(left: (true, 0, 20_000), right: (true, 0, 20_000)),
            .init(left: (true, 20_000, 0), right: (true, 0, 20_000)),
            .init(left: (true, 20_000, 0), right: (false, 0, 20_000)),
            .init(left: (false, 20_000, 0), right: (false, 0, 20_000))
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.left.dpadKeys.right = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "space"

        let result = try run(configuration: configuration, hid: hid, output: output)

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 4, actionCount: 2))
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testSharedMouseButtonStaysHeldUntilBothPadsLift() throws {
        let output = RecordingOutput()
        let hid = ScriptedTrackpadHID(reports: [
            .init(left: (true, 0, 20_000), right: (true, 0, 20_000)),
            .init(left: (false, 0, 20_000), right: (true, 0, 20_000)),
            .init(left: (false, 0, 20_000), right: (false, 0, 20_000))
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = TapBindingCatalog.leftMouseButton
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = TapBindingCatalog.leftMouseButton

        let result = try run(configuration: configuration, hid: hid, output: output)

        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 3, actionCount: 2))
        XCTAssertEqual(output.actions, [
            .mouseButton(.left, isPressed: true),
            .mouseButton(.left, isPressed: false)
        ])
    }

    func testDeviceRemovalWithSharedZoneBindingReleasesOutputOnce() throws {
        let output = RecordingOutput()
        let hid = ScriptedTrackpadHID(
            reports: [.init(left: (true, 0, 20_000), right: (true, 0, 20_000))],
            termination: .deviceRemoved
        )
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "space"

        let result = try run(configuration: configuration, hid: hid, output: output)

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.termination, .deviceRemoved)
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testDeviceRemovalStopsReportsAndReleasesHeldOutputOnce() throws {
        let output = RecordingOutput()
        let hid = RemovingHID()
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: false,
            stopToken: TrackpadStopToken(),
            dependencies: TrackpadRuntimeDependencies(
                openHID: { hid },
                makeOutput: { output }
            )
        )

        XCTAssertEqual(result.termination, .deviceRemoved)
        XCTAssertEqual(result.summary.reportCount, 1)
        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testDeviceRemovalAttemptsEveryReleaseAndSurfacesAggregateFailure() throws {
        let output = FailingReleaseOutput()
        let hid = RemovingBothPadsHID()
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "return"

        XCTAssertThrowsError(
            try TrackpadRuntime.run(
                configuration: configuration,
                observeOnly: false,
                stopToken: TrackpadStopToken(),
                dependencies: TrackpadRuntimeDependencies(
                    openHID: { hid },
                    makeOutput: { output }
                )
            )
        ) { error in
            let description = String(describing: error)
            XCTAssertTrue(description.contains("release held outputs"))
            XCTAssertTrue(description.contains("key space up"))
            XCTAssertTrue(description.contains("key return up"))
        }

        let space = try KeyCatalog.resolve("space")
        let returnKey = try KeyCatalog.resolve("return")
        XCTAssertEqual(output.releaseAttempts, [
            .key(space, isPressed: false),
            .key(returnKey, isPressed: false)
        ])
    }

    private func run<HID: TrackpadHIDStreaming & Sendable>(
        configuration: TrackIsBackConfiguration,
        hid: HID,
        output: any TrackpadOutputDispatching
    ) throws -> TrackpadRunResult {
        try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: false,
            stopToken: TrackpadStopToken(),
            dependencies: TrackpadRuntimeDependencies(
                openHID: { hid },
                makeOutput: { output }
            )
        )
    }
}

private final class ScriptedTrackpadHID: TrackpadHIDStreaming, Sendable {
    struct Report: Sendable {
        let left: (touched: Bool, x: Int16, y: Int16)
        let right: (touched: Bool, x: Int16, y: Int16)
    }

    let summaryDescription = "Fake puck"
    let reports: [Report]
    let termination: TrackpadStreamTermination

    init(reports: [Report], termination: TrackpadStreamTermination = .stopped) {
        self.reports = reports
        self.termination = termination
    }

    func stream(
        shouldContinue: () -> Bool,
        onReport: ([UInt8], UInt64) throws -> Void
    ) throws -> TrackpadStreamTermination {
        for (index, report) in reports.enumerated() {
            guard shouldContinue() else { return .stopped }
            try onReport(bytes(for: report), UInt64(index + 1))
        }
        return termination
    }

    private func bytes(for report: Report) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 54)
        bytes[0] = 0x42
        let buttons: UInt32 = (report.left.touched ? 0x0200_0000 : 0)
            | (report.right.touched ? 0x0020_0000 : 0)
        for offset in 0..<4 {
            bytes[2 + offset] = UInt8(truncatingIfNeeded: buttons >> (offset * 8))
        }
        write(report.left.x, to: &bytes, at: 18)
        write(report.left.y, to: &bytes, at: 20)
        write(report.right.x, to: &bytes, at: 24)
        write(report.right.y, to: &bytes, at: 26)
        return bytes
    }

    private func write(_ value: Int16, to bytes: inout [UInt8], at offset: Int) {
        let unsigned = UInt16(bitPattern: value)
        bytes[offset] = UInt8(truncatingIfNeeded: unsigned)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: unsigned >> 8)
    }
}

private final class RemovingHID: TrackpadHIDStreaming, Sendable {
    let summaryDescription = "Fake puck"

    func stream(
        shouldContinue: () -> Bool,
        onReport: ([UInt8], UInt64) throws -> Void
    ) throws -> TrackpadStreamTermination {
        XCTAssertTrue(shouldContinue())
        try onReport(report(touched: true, x: 0, y: 20_000), 1)
        return .deviceRemoved
    }

    private func report(touched: Bool, x: Int16, y: Int16) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 54)
        bytes[0] = 0x42
        let buttons: UInt32 = touched ? 0x0200_0000 : 0
        for offset in 0..<4 { bytes[2 + offset] = UInt8(truncatingIfNeeded: buttons >> (offset * 8)) }
        write(x, to: &bytes, at: 18)
        write(y, to: &bytes, at: 20)
        return bytes
    }

    private func write(_ value: Int16, to bytes: inout [UInt8], at offset: Int) {
        let unsigned = UInt16(bitPattern: value)
        bytes[offset] = UInt8(truncatingIfNeeded: unsigned)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: unsigned >> 8)
    }
}

private final class RecordingOutput: TrackpadOutputDispatching, Sendable {
    private let storage = Mutex<[TrackpadOutputAction]>([])
    var actions: [TrackpadOutputAction] { storage.withLock { $0 } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        storage.withLock { $0.append(contentsOf: actions) }
    }
}

private final class RemovingBothPadsHID: TrackpadHIDStreaming, Sendable {
    let summaryDescription = "Fake puck"

    func stream(
        shouldContinue: () -> Bool,
        onReport: ([UInt8], UInt64) throws -> Void
    ) throws -> TrackpadStreamTermination {
        XCTAssertTrue(shouldContinue())
        var bytes = [UInt8](repeating: 0, count: 54)
        bytes[0] = 0x42
        let buttons: UInt32 = 0x0220_0000
        for offset in 0..<4 { bytes[2 + offset] = UInt8(truncatingIfNeeded: buttons >> (offset * 8)) }
        write(20_000, to: &bytes, at: 20)
        write(20_000, to: &bytes, at: 26)
        try onReport(bytes, 1)
        return .deviceRemoved
    }

    private func write(_ value: Int16, to bytes: inout [UInt8], at offset: Int) {
        let unsigned = UInt16(bitPattern: value)
        bytes[offset] = UInt8(truncatingIfNeeded: unsigned)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: unsigned >> 8)
    }
}

private final class FailingReleaseOutput: TrackpadOutputDispatching, Sendable {
    private let releaseStorage = Mutex<[TrackpadOutputAction]>([])
    var releaseAttempts: [TrackpadOutputAction] { releaseStorage.withLock { $0 } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions where action.isReleaseForTesting {
            releaseStorage.withLock { $0.append(action) }
            throw TrackIsBackError.output("Injected release failure.")
        }
    }
}

private extension TrackpadOutputAction {
    var isReleaseForTesting: Bool {
        switch self {
        case let .key(_, isPressed), let .mouseButton(_, isPressed): !isPressed
        case .mouseMove, .scroll: false
        }
    }
}
