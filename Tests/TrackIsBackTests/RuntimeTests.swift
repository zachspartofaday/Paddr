import Foundation
import Synchronization
import XCTest
@testable import TrackIsBackCore

final class RuntimeTests: XCTestCase {
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
