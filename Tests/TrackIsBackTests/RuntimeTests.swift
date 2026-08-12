import Foundation
import Synchronization
import XCTest
@testable import TrackIsBackCore

final class RuntimeTests: XCTestCase {
    func testBothPadsEmitDistinctZoneBindingsAndReleaseIndependently() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .report(report(leftTouched: false, rightTouched: true), at: 20),
            .report(neutralReport(), at: 30)
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "return"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        let space = try KeyCatalog.resolve("space")
        let returnKey = try KeyCatalog.resolve("return")
        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 4, actionCount: 4))
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(returnKey, isPressed: true),
            .key(space, isPressed: false),
            .key(returnKey, isPressed: false)
        ])
    }

    func testSharedZoneBindingSurvivesCrossingAndOtherPadLiftUntilLastOwnerLifts() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .report(
                report(leftTouched: true, rightTouched: true, leftX: 20_000, leftY: 0),
                at: 20
            ),
            .report(
                report(leftTouched: true, rightTouched: false, leftX: 20_000, leftY: 0),
                at: 30
            ),
            .report(neutralReport(), at: 40)
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.left.dpadKeys.right = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 5, actionCount: 2))
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testSharedMouseButtonStaysHeldUntilBothPadsLift() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .report(report(leftTouched: false, rightTouched: true), at: 20),
            .report(neutralReport(), at: 30)
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = TapBindingCatalog.leftMouseButton
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = TapBindingCatalog.leftMouseButton

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 4, actionCount: 2))
        XCTAssertEqual(output.actions, [
            .mouseButton(.left, isPressed: true),
            .mouseButton(.left, isPressed: false)
        ])
    }

    func testDeviceRemovalWithSharedZoneBindingReleasesOutputOnce() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .remove
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.termination, .deviceRemoved)
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testReceiverOpenAndSilenceNeverPublishesControllerPresenceOrOutputArmed() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [.wake(at: 2_000_000_000), .stop])
        let events = EventRecorder()

        let result = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(result.termination, .stopped)
        XCTAssertEqual(result.summary, .init(reportCount: 0, actionCount: 0))
        XCTAssertEqual(events.events, [.waitingForController("Fake receiver")])
    }

    func testFirstParsedReportConnectsOnceAndOutputArmsOnlyAfterNeutral() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(heldLeftReport(), at: 0),
            .report(heldLeftReport(), at: 100_000_000),
            .report(neutralReport(), at: 200_000_000),
            .remove
        ])
        let events = EventRecorder()
        let output = RecordingOutput()

        let result = try run(hid: hid, clock: clock, output: output, events: events)

        XCTAssertEqual(result.summary.reportCount, 3)
        XCTAssertEqual(events.events, [
            .waitingForController("Fake receiver"),
            .controllerConnected,
            .outputArmed
        ])
        XCTAssertEqual(output.actions, [])
    }

    func testUnknownAndInvalidReportsDoNotRefreshDeadlineAndLossOccursAtExactlyOneSecond() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 10),
            .report(unknownReport(), at: 500_000_000),
            .report([0x42], at: 999_999_999),
            .wake(at: 1_000_000_010),
            .stop
        ])
        let events = EventRecorder()

        let result = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(result.summary.reportCount, 1)
        XCTAssertEqual(events.events, [
            .waitingForController("Fake receiver"),
            .controllerConnected,
            .outputArmed,
            .controllerLost(.init(reportCount: 1, actionCount: 0))
        ])
    }

    func testDeadlineDoesNotFireJustBeforeOneSecondAndParsedReportRefreshesIt() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 100),
            .wake(at: 1_000_000_098),
            .report(neutralReport(), at: 1_000_000_099),
            .wake(at: 2_000_000_098),
            .wake(at: 2_000_000_099),
            .stop
        ])
        let events = EventRecorder()

        let result = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(result.summary.reportCount, 2)
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.events.last, .controllerLost(.init(reportCount: 2, actionCount: 0)))
    }

    func testDelayedDrainUsesReportReceiptTimeToReleaseHeldOutputAtDeadline() throws {
        let clock = ManualUptimeClock()
        let timeline = TimelineRecorder()
        let output = RecordingOutput { action in timeline.append(action.description) }
        let events = EventRecorder { event in timeline.append(String(describing: event)) }
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .delayedReport(
                heldLeftReport(),
                receivedAt: 10,
                processedAt: 1_000_000_010
            ),
            .wake(at: 1_000_000_010),
            .stop
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        let entries = timeline.entries
        let lostIndex = try XCTUnwrap(entries.firstIndex { $0.contains("controllerLost") })
        XCTAssertLessThan(try XCTUnwrap(entries.firstIndex(of: "key space up")), lostIndex)
    }

    func testAcceptedReportAfterReceiveGapCleansUpBeforeStartingFreshEpoch() throws {
        let clock = ManualUptimeClock()
        let timeline = TimelineRecorder()
        let output = RecordingOutput { action in timeline.append(action.description) }
        let events = EventRecorder { event in timeline.append(String(describing: event)) }
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .report(heldLeftReport(), at: 1_000_000_011),
            .wake(at: 1_000_000_011),
            .report(neutralReport(), at: 1_100_000_000),
            .report(heldLeftReport(), at: 1_200_000_000),
            .stop
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false),
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
        XCTAssertTrue(events.events.contains(.controllerLost(.init(reportCount: 2, actionCount: 1))))
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 2)

        let entries = timeline.entries
        let releaseIndex = try XCTUnwrap(entries.firstIndex(of: "key space up"))
        let lostIndex = try XCTUnwrap(entries.firstIndex { $0.contains("controllerLost") })
        let reconnectIndex = try XCTUnwrap(
            entries.indices.dropFirst(lostIndex + 1).first { entries[$0].contains("controllerConnected") }
        )
        let rearmIndex = try XCTUnwrap(
            entries.indices.dropFirst(reconnectIndex + 1).first { entries[$0].contains("outputArmed") }
        )
        let freshPressIndex = try XCTUnwrap(
            entries.indices.dropFirst(rearmIndex + 1).first { entries[$0] == "key space down" }
        )
        XCTAssertLessThan(releaseIndex, lostIndex)
        XCTAssertLessThan(lostIndex, reconnectIndex)
        XCTAssertLessThan(reconnectIndex, rearmIndex)
        XCTAssertLessThan(rearmIndex, freshPressIndex)
    }

    func testLossReleasesDistinctKeyAndMouseBeforePublishingLost() throws {
        let clock = ManualUptimeClock()
        let timeline = TimelineRecorder()
        let output = RecordingOutput { action in timeline.append(action.description) }
        let events = EventRecorder { event in timeline.append(String(describing: event)) }
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .wake(at: 1_000_000_010),
            .stop
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = TapBindingCatalog.leftMouseButton

        _ = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .mouseButton(.left, isPressed: true),
            .key(space, isPressed: false),
            .mouseButton(.left, isPressed: false)
        ])
        let entries = timeline.entries
        let lostIndex = try XCTUnwrap(entries.firstIndex { $0.contains("controllerLost") })
        XCTAssertLessThan(try XCTUnwrap(entries.firstIndex(of: "key space up")), lostIndex)
        XCTAssertLessThan(try XCTUnwrap(entries.firstIndex(of: "mouse left up")), lostIndex)
    }

    func testLossReleasesSharedKeyAndMouseOwnershipExactlyOnceAcrossTimeoutRemovalRace() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .wake(at: 1_000_000_010),
            .remove
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.termination, .deviceRemoved)
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)

        let mouseClock = ManualUptimeClock()
        let mouseOutput = RecordingOutput()
        let mouseHID = ScriptedHID(clock: mouseClock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .wake(at: 1_000_000_010),
            .remove
        ])
        configuration.left.dpadKeys.up = TapBindingCatalog.leftMouseButton
        configuration.right.dpadKeys.up = TapBindingCatalog.leftMouseButton

        _ = try run(
            configuration: configuration,
            hid: mouseHID,
            clock: mouseClock,
            output: mouseOutput,
            events: EventRecorder()
        )
        XCTAssertEqual(mouseOutput.actions, [
            .mouseButton(.left, isPressed: true),
            .mouseButton(.left, isPressed: false)
        ])
    }

    func testReleaseFailureIsTerminalAndDoesNotPublishControllerLost() throws {
        let clock = ManualUptimeClock()
        let output = FailingReleaseOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .wake(at: 1_000_000_010),
            .stop
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        XCTAssertThrowsError(
            try run(
                configuration: configuration,
                hid: hid,
                clock: clock,
                output: output,
                events: events
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("release held outputs"))
        }
        XCTAssertFalse(events.events.contains { if case .controllerLost = $0 { true } else { false } })
        XCTAssertEqual(output.releaseAttempts.count, 1)
    }

    func testCleanupAttemptsEveryReleaseAndSurfacesAggregateFailure() throws {
        let clock = ManualUptimeClock()
        let output = FailingReleaseOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .remove
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "return"

        XCTAssertThrowsError(
            try run(
                configuration: configuration,
                hid: hid,
                clock: clock,
                output: output,
                events: EventRecorder()
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

    func testObserveOnlyLossResetsEpochWithoutDispatching() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .wake(at: 1_000_000_010),
            .report(heldLeftReport(), at: 1_100_000_000),
            .report(neutralReport(), at: 1_200_000_000),
            .remove
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            observeOnly: true,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertEqual(output.actions, [])
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 2)
    }

    func testReappearanceRequiresFreshEvidenceAndNeutralBeforeHeldInputCanPressAgain() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .wake(at: 1_000_000_010),
            .report(heldLeftReport(), at: 1_100_000_000),
            .report(neutralReport(), at: 1_200_000_000),
            .report(heldLeftReport(), at: 1_300_000_000),
            .remove
        ])
        var configuration = TrackIsBackConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false),
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 2)
    }

    private func run(
        configuration: TrackIsBackConfiguration = .default,
        observeOnly: Bool = false,
        hid: ScriptedHID,
        clock: ManualUptimeClock,
        output: any TrackpadOutputDispatching = RecordingOutput(),
        events: EventRecorder
    ) throws -> TrackpadRunResult {
        try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: observeOnly,
            stopToken: TrackpadStopToken(),
            dependencies: TrackpadRuntimeDependencies(
                openHID: { hid },
                makeOutput: { output },
                uptimeNanoseconds: { clock.now }
            ),
            onEvent: events.record
        )
    }
}

private final class ManualUptimeClock: Sendable {
    private let storage = Mutex<UInt64>(0)
    var now: UInt64 { storage.withLock { $0 } }
    func set(_ value: UInt64) { storage.withLock { $0 = value } }
}

private final class ScriptedHID: TrackpadHIDStreaming, Sendable {
    enum Step: Sendable {
        case report([UInt8], at: UInt64)
        case delayedReport([UInt8], receivedAt: UInt64, processedAt: UInt64)
        case wake(at: UInt64)
        case remove
        case stop
    }

    let summaryDescription = "Fake receiver"
    private let clock: ManualUptimeClock
    private let steps: [Step]

    init(clock: ManualUptimeClock, steps: [Step]) {
        self.clock = clock
        self.steps = steps
    }

    func stream(
        shouldContinue: () -> Bool,
        onWake: () throws -> Void,
        onReport: ([UInt8], UInt64) throws -> Void
    ) throws -> TrackpadStreamTermination {
        for step in steps {
            guard shouldContinue() else { return .stopped }
            switch step {
            case let .report(bytes, uptime):
                clock.set(uptime)
                try onReport(bytes, uptime)
            case let .delayedReport(bytes, receivedAt, processedAt):
                clock.set(processedAt)
                try onReport(bytes, receivedAt)
            case let .wake(uptime):
                clock.set(uptime)
                try onWake()
            case .remove:
                return .deviceRemoved
            case .stop:
                return .stopped
            }
        }
        return .stopped
    }
}

private final class RecordingOutput: TrackpadOutputDispatching, Sendable {
    private struct Storage: ~Copyable {
        var actions: [TrackpadOutputAction] = []
    }
    private let storage = Mutex(Storage())
    private let onAction: @Sendable (TrackpadOutputAction) -> Void

    init(onAction: @escaping @Sendable (TrackpadOutputAction) -> Void = { _ in }) {
        self.onAction = onAction
    }

    var actions: [TrackpadOutputAction] { storage.withLock { $0.actions } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        storage.withLock { $0.actions.append(contentsOf: actions) }
        for action in actions { onAction(action) }
    }
}

private final class EventRecorder: Sendable {
    private let storage = Mutex<[TrackpadSessionEvent]>([])
    private let onEvent: @Sendable (TrackpadSessionEvent) -> Void

    init(onEvent: @escaping @Sendable (TrackpadSessionEvent) -> Void = { _ in }) {
        self.onEvent = onEvent
    }

    var events: [TrackpadSessionEvent] { storage.withLock { $0 } }

    func record(_ event: TrackpadSessionEvent) {
        storage.withLock { $0.append(event) }
        onEvent(event)
    }
}

private final class TimelineRecorder: Sendable {
    private let storage = Mutex<[String]>([])
    var entries: [String] { storage.withLock { $0 } }
    func append(_ entry: String) { storage.withLock { $0.append(entry) } }
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

private func neutralReport() -> [UInt8] {
    report(leftTouched: false, rightTouched: false)
}

private func heldLeftReport() -> [UInt8] {
    report(leftTouched: true, rightTouched: false)
}

private func unknownReport() -> [UInt8] {
    var bytes = neutralReport()
    bytes[0] = 0x99
    return bytes
}

private func report(
    leftTouched: Bool,
    rightTouched: Bool,
    leftX: Int16 = 0,
    leftY: Int16 = 20_000,
    rightX: Int16 = 0,
    rightY: Int16 = 20_000
) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 54)
    bytes[0] = 0x42
    var buttons: UInt32 = 0
    if leftTouched { buttons |= 0x0200_0000 }
    if rightTouched { buttons |= 0x0020_0000 }
    for offset in 0..<4 {
        bytes[2 + offset] = UInt8(truncatingIfNeeded: buttons >> (offset * 8))
    }
    write(leftX, to: &bytes, at: 18)
    write(leftY, to: &bytes, at: 20)
    write(rightX, to: &bytes, at: 24)
    write(rightY, to: &bytes, at: 26)
    return bytes
}

private func write(_ value: Int16, to bytes: inout [UInt8], at offset: Int) {
    let unsigned = UInt16(bitPattern: value)
    bytes[offset] = UInt8(truncatingIfNeeded: unsigned)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: unsigned >> 8)
}

private extension TrackpadOutputAction {
    var isReleaseForTesting: Bool {
        switch self {
        case let .key(_, isPressed), let .mouseButton(_, isPressed): !isPressed
        case .mouseMove, .scroll: false
        }
    }
}
