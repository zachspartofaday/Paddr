import Foundation
import Synchronization
import XCTest
@testable import PaddrCore

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
        var configuration = PaddrConfiguration.default
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
        var configuration = PaddrConfiguration.default
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
        var configuration = PaddrConfiguration.default
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
        var configuration = PaddrConfiguration.default
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

    func testDelayedDrainRejectsExpiredPressBeforeMapping() throws {
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
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertTrue(output.actions.isEmpty)
        XCTAssertTrue(timeline.entries.contains { $0.contains("controllerLost") })
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
        var configuration = PaddrConfiguration.default
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
        var configuration = PaddrConfiguration.default
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
        var configuration = PaddrConfiguration.default
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
        var configuration = PaddrConfiguration.default
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
        XCTAssertEqual(output.releaseAttempts.count, 5)
    }

    func testCleanupAttemptsEveryReleaseAndSurfacesAggregateFailure() throws {
        let clock = ManualUptimeClock()
        let output = FailingReleaseOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .remove
        ])
        var configuration = PaddrConfiguration.default
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
            .key(returnKey, isPressed: false),
            .key(returnKey, isPressed: false),
            .key(space, isPressed: false),
            .key(returnKey, isPressed: false),
            .key(space, isPressed: false)
        ])
    }

    func testFailOnceReleaseRetriesBeforePublishingControllerLost() throws {
        let clock = ManualUptimeClock()
        let output = FailOnceReleaseOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .wake(at: 1_000_000_010),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.termination, .stopped)
        XCTAssertEqual(output.attempts, [
            .key(space, isPressed: true),
            .key(space, isPressed: false),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(output.committed, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(
            events.events.filter { if case .controllerLost = $0 { true } else { false } }.count,
            1
        )
    }

    func testFailOnceGateReleaseRetriesBeforePublishingAcknowledgement() throws {
        let clock = ManualUptimeClock()
        let output = FailOnceReleaseOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: true)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .perform { gate.setEnabled(false) },
            .wake(at: 20),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            outputGate: gate,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertEqual(outputReleasedEvents(in: events.events), [.outputReleased(revision: 1)])
    }

    func testFailOnceDeviceRemovalReleasePreservesDeviceTermination() throws {
        let clock = ManualUptimeClock()
        let output = FailOnceReleaseOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .remove
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        XCTAssertEqual(result.termination, .deviceRemoved)
    }

    func testFailOnceStopReleasePreservesStoppedTermination() throws {
        let clock = ManualUptimeClock()
        let output = FailOnceReleaseOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        XCTAssertEqual(result.termination, .stopped)
    }

    func testPersistentGateReleaseDoesNotPublishAcknowledgement() throws {
        let clock = ManualUptimeClock()
        let output = FailingReleaseOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: true)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .perform { gate.setEnabled(false) },
            .wake(at: 20),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        XCTAssertThrowsError(try run(
            configuration: configuration,
            outputGate: gate,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        ))

        XCTAssertEqual(outputReleasedEvents(in: events.events), [])
    }

    func testPartialNormalBatchPublishesNothingAndReleasesSuccessfulPrefix() throws {
        let clock = ManualUptimeClock()
        let output = FailingCallOutput(failingCalls: [2])
        let events = EventRecorder()
        let publishedActions = StringRecorder()
        let token = TrackpadStopToken()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(report(leftTouched: true, rightTouched: true), at: 10),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"
        configuration.right.mode = .dpad
        configuration.right.dpadKeys.up = "return"

        XCTAssertThrowsError(try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: false,
            stopToken: token,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { hid },
                makeOutput: { output },
                uptimeNanoseconds: { clock.now }
            ),
            onEvent: events.record,
            onAction: publishedActions.append
        ))

        let space = try KeyCatalog.resolve("space")
        let returnKey = try KeyCatalog.resolve("return")
        XCTAssertEqual(output.attempts, [
            .key(space, isPressed: true),
            .key(returnKey, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(output.committed, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(publishedActions.values, [])
        XCTAssertFalse(token.hasPendingOutputs)
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
        var configuration = PaddrConfiguration.default
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

    func testGateDisabledReportsConnectControllerWithoutAnyOutput() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: false)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .report(neutralReport(), at: 20)
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            outputGate: gate,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertTrue(events.events.contains(.controllerConnected))
        XCTAssertFalse(events.events.contains(.outputArmed))
        XCTAssertEqual(outputReleasedEvents(in: events.events).count, 1)
        XCTAssertEqual(events.events.first, .waitingForController("Fake receiver"))
        XCTAssertEqual(events.events.dropFirst().first, .outputReleased(revision: 0))
        XCTAssertEqual(output.actions, [])
        XCTAssertEqual(result.summary, TrackpadRunSummary(reportCount: 3, actionCount: 0))
    }

    func testGateEnableWhileHeldWaitsForFreshNeutralBeforeArming() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: false)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(heldLeftReport(), at: 0),
            .perform { gate.setEnabled(true) },
            .report(heldLeftReport(), at: 10),
            .report(heldLeftReport(), at: 20),
            .report(neutralReport(), at: 30),
            .report(heldLeftReport(), at: 40),
            .report(neutralReport(), at: 50)
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            outputGate: gate,
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
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 1)
    }

    func testGateDisableReleasesHeldOutputBeforeEmittingOutputReleased() throws {
        let clock = ManualUptimeClock()
        let timeline = TimelineRecorder()
        let output = RecordingOutput { action in
            timeline.append("action:\(action.description)")
        }
        let events = EventRecorder { event in
            switch event {
            case .outputReleased: timeline.append("event:outputReleased")

            case .controllerConnected: timeline.append("event:controllerConnected")
            case .controllerLost: timeline.append("event:controllerLost")
            default: break
            }
        }
        let gate = OutputGate(enabled: true)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .perform { gate.setEnabled(false) },
            .wake(at: 20),
            .report(neutralReport(), at: 30),
            .report(heldLeftReport(), at: 40)
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            outputGate: gate,
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
        XCTAssertEqual(timeline.entries, [
            "event:controllerConnected",
            "action:\(TrackpadOutputAction.key(space, isPressed: true).description)",
            "action:\(TrackpadOutputAction.key(space, isPressed: false).description)",
            "event:outputReleased"
        ])
        XCTAssertFalse(events.events.contains { event in
            if case .controllerLost = event { return true }
            return false
        })
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 1)
        XCTAssertEqual(result.termination, .stopped)
    }

    func testGateReenableAfterDisableArmsOnlyOnFreshNeutral() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: true)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .perform { gate.setEnabled(false) },
            .wake(at: 20),
            .perform { gate.setEnabled(true) },
            .report(heldLeftReport(), at: 30),
            .report(neutralReport(), at: 40),
            .report(heldLeftReport(), at: 50),
            .report(neutralReport(), at: 60)
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        _ = try run(
            configuration: configuration,
            outputGate: gate,
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
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 2)
        XCTAssertEqual(outputReleasedEvents(in: events.events).count, 1)
    }

    func testGateDisableWithNothingHeldStillEmitsOutputReleasedAndKeepsLiveness() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: true)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .perform { gate.setEnabled(false) },
            .wake(at: 10),
            .report(neutralReport(), at: 20)
        ])

        _ = try run(
            configuration: .default,
            outputGate: gate,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertEqual(output.actions, [])
        XCTAssertEqual(outputReleasedEvents(in: events.events).count, 1)
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 1)
    }

    func testControllerLossWhileGateDisabledPublishesLostWithoutOutput() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: false)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .wake(at: 1_000_000_000),
            .report(neutralReport(), at: 1_500_000_000)
        ])

        _ = try run(
            configuration: .default,
            outputGate: gate,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertEqual(output.actions, [])
        XCTAssertEqual(
            events.events.filter { event in
                if case .controllerLost = event { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)
    }

    func testCoalescedEnableDisableStillAcknowledgesTheNewerDisabledRevision() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate(enabled: false)
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .perform {
                gate.setEnabled(true)
                gate.setEnabled(false)
            },
            .wake(at: 10),
            .report(neutralReport(), at: 20)
        ])

        _ = try run(
            configuration: .default,
            outputGate: gate,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertEqual(output.actions, [])
        XCTAssertTrue(events.events.contains(.outputReleased(revision: 0)))
        XCTAssertTrue(events.events.contains(.outputReleased(revision: 2)))
        XCTAssertEqual(outputReleasedEvents(in: events.events).count, 2)
    }

    func testObserveOnlyStaysHardNoOutputEvenWithGateEnabled() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .report(neutralReport(), at: 20)
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            observeOnly: true,
            outputGate: OutputGate(enabled: true),
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        XCTAssertEqual(output.actions, [])
        XCTAssertEqual(result.summary.actionCount, 2)
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
        var configuration = PaddrConfiguration.default
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

    func testWirelessConnectStatusMarksControllerLiveWithoutStateReports() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report([0x46, 2], at: 10),
            .stop
        ])
        let events = EventRecorder()
        let output = RecordingOutput()

        let result = try run(hid: hid, clock: clock, output: output, events: events)

        XCTAssertEqual(result.summary.reportCount, 0)
        XCTAssertEqual(events.events, [
            .waitingForController("Fake receiver"),
            .controllerConnected
        ])
        XCTAssertEqual(output.actions, [])
    }

    func testWirelessDisconnectReleasesHeldOutputsBeforeControllerLost() throws {
        let clock = ManualUptimeClock()
        let timeline = TimelineRecorder()
        let output = RecordingOutput { action in timeline.append(action.description) }
        let events = EventRecorder { event in timeline.append(String(describing: event)) }
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .report([0x79, 1], at: 20),
            .report(neutralReport(), at: 30),
            .stop
        ])
        var configuration = PaddrConfiguration.default
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
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
        XCTAssertTrue(events.events.contains(.controllerLost(.init(reportCount: 2, actionCount: 1))))
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)

        let entries = timeline.entries
        let releaseIndex = try XCTUnwrap(entries.firstIndex(of: "key space up"))
        let lostIndex = try XCTUnwrap(entries.firstIndex { $0.contains("controllerLost") })
        XCTAssertLessThan(releaseIndex, lostIndex)
    }

    func testWirelessConnectStatusRefreshesLivenessDeadline() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report([0x46, 2], at: 900_000_000),
            .wake(at: 1_899_999_999),
            .wake(at: 1_900_000_000),
            .stop
        ])
        let events = EventRecorder()

        let result = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(result.summary.reportCount, 1)
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 1)
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.events.last, .controllerLost(.init(reportCount: 1, actionCount: 0)))
    }

    func testWirelessDisconnectWhileNotLiveEmitsNothing() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report([0x46, 1], at: 10),
            .stop
        ])
        let events = EventRecorder()

        _ = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(events.events, [.waitingForController("Fake receiver")])
    }

    func testWirelessConnectDrainedAfterDeadlineReleasesHeldOutputsFirst() throws {
        let clock = ManualUptimeClock()
        let timeline = TimelineRecorder()
        let output = RecordingOutput { action in timeline.append(action.description) }
        let events = EventRecorder { event in timeline.append(String(describing: event)) }
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .report([0x46, 2], at: 1_000_000_011),
            .stop
        ])
        var configuration = PaddrConfiguration.default
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
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)

        let entries = timeline.entries
        let releaseIndex = try XCTUnwrap(entries.firstIndex(of: "key space up"))
        let lostIndex = try XCTUnwrap(entries.firstIndex { $0.contains("controllerLost") })
        XCTAssertLessThan(releaseIndex, lostIndex)
    }

    func testBatteryReportsRequireAnAlreadyActiveSlotAndDoNotAffectOutputState() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(batteryReport(chargeState: 1, percentage: 40), at: 0),
            .slotReport(1, [0x46, 2], at: 10),
            .slotReport(0, batteryReport(chargeState: 2, percentage: 60), at: 20),
            .slotReport(1, batteryReport(chargeState: 2, percentage: 82), at: 30),
            .stop
        ])

        let result = try run(hid: hid, clock: clock, output: output, events: events)

        XCTAssertEqual(result.summary, .init(reportCount: 0, actionCount: 0))
        XCTAssertEqual(events.events, [
            .waitingForController("Fake receiver"),
            .controllerConnected,
            .batteryUpdated(.init(chargeState: .charging, percentage: 82))
        ])
        XCTAssertFalse(events.events.contains(.outputArmed))
        XCTAssertEqual(output.actions, [])
    }

    func testBatteryDoesNotRefreshLivenessAndCannotPublishOrReacquireAtDeadline() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let hid = ScriptedHID(clock: clock, steps: [
            .report([0x46, 2], at: 0),
            .report(batteryReport(chargeState: 1, percentage: 25), at: 999_999_999),
            .report(batteryReport(chargeState: 2, percentage: 50), at: 1_000_000_000),
            .slotReport(1, batteryReport(chargeState: 2, percentage: 60), at: 1_000_000_001),
            .slotReport(1, [0x46, 2], at: 1_100_000_000),
            .slotReport(1, batteryReport(chargeState: 0xFE, percentage: 75), at: 1_100_000_001),
            .stop
        ])

        let result = try run(hid: hid, clock: clock, output: output, events: events)

        XCTAssertEqual(result.summary, .init(reportCount: 0, actionCount: 0))
        XCTAssertEqual(events.events, [
            .waitingForController("Fake receiver"),
            .controllerConnected,
            .batteryUpdated(.init(chargeState: .discharging, percentage: 25)),
            .controllerLost(.init(reportCount: 0, actionCount: 0)),
            .controllerConnected,
            .batteryUpdated(.init(chargeState: .unknown(0xFE), percentage: 75))
        ])
        XCTAssertFalse(events.events.contains(.outputArmed))
        XCTAssertEqual(output.actions, [])
    }

    func testOtherSlotReportsAndDisconnectsAreIgnoredWhileSlotActive() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .slotReport(1, neutralReport(), at: 20),
            .slotReport(1, [0x46, 2], at: 25),
            .slotReport(1, [0x79, 1], at: 30),
            .slotReport(0, [0x79, 1], at: 40),
            .stop
        ])
        let events = EventRecorder()
        let output = RecordingOutput()
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            hid: hid,
            clock: clock,
            output: output,
            events: events
        )

        XCTAssertEqual(result.summary.reportCount, 2)
        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 1)
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.events.last, .controllerLost(.init(reportCount: 2, actionCount: 1)))
    }

    func testControllerAdoptsNewSlotAfterLoss() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .slotReport(1, neutralReport(), at: 10),
            .wake(at: 1_100_000_000),
            .slotReport(2, neutralReport(), at: 1_200_000_000),
            .stop
        ])
        let events = EventRecorder()

        let result = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(result.summary.reportCount, 2)
        XCTAssertEqual(events.events.filter { $0 == .controllerConnected }.count, 2)
        XCTAssertEqual(events.events.filter { if case .controllerLost = $0 { true } else { false } }.count, 1)
    }

    func testUnpadded46ByteStateReportDrivesControllerConnection() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(Array(neutralReport().prefix(46)), at: 10),
            .stop
        ])
        let events = EventRecorder()

        let result = try run(hid: hid, clock: clock, events: events)

        XCTAssertEqual(result.summary.reportCount, 1)
        XCTAssertEqual(events.events, [
            .waitingForController("Fake receiver"),
            .controllerConnected,
            .outputArmed
        ])
    }

    func testDurationStopsAtExactMonotonicBoundaryAndReleasesHeldOutput() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .perform { clock.set(20) },
            .report(neutralReport(), at: 20)
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        let result = try run(
            configuration: configuration,
            duration: .nanoseconds(20),
            hid: hid,
            clock: clock,
            output: output,
            events: EventRecorder()
        )

        let space = try KeyCatalog.resolve("space")
        XCTAssertEqual(result.termination, .stopped)
        XCTAssertEqual(result.summary.reportCount, 2)
        XCTAssertEqual(output.actions, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testDurationAllowsWorkImmediatelyBeforeMonotonicBoundary() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .perform { clock.set(20) },
            .report(neutralReport(), at: 20),
            .stop
        ])

        let result = try run(
            duration: .nanoseconds(21),
            hid: hid,
            clock: clock,
            events: EventRecorder()
        )

        XCTAssertEqual(result.termination, .stopped)
        XCTAssertEqual(result.summary.reportCount, 2)
    }

    func testDurationStopsAfterMonotonicBoundary() throws {
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0),
            .perform { clock.set(21) },
            .report(neutralReport(), at: 21)
        ])

        let result = try run(
            duration: .nanoseconds(20),
            hid: hid,
            clock: clock,
            events: EventRecorder()
        )

        XCTAssertEqual(result.termination, .stopped)
        XCTAssertEqual(result.summary.reportCount, 1)
    }

    func testDurationValidationRejectsZeroAndNanosecondOverflow() throws {
        XCTAssertThrowsError(try TrackpadRuntime.validatedDurationNanoseconds(.zero))
        XCTAssertThrowsError(
            try TrackpadRuntime.validatedDurationNanoseconds(.seconds(Int64.max))
        )
        XCTAssertEqual(
            try TrackpadRuntime.validatedDurationNanoseconds(.nanoseconds(1)),
            1
        )
    }

    func testPublicStopTokenCanBeReusedAfterADrainedRun() throws {
        let stopToken = TrackpadStopToken()

        for timestamp in [UInt64(10), UInt64(20)] {
            let clock = ManualUptimeClock()
            let hid = ScriptedHID(clock: clock, steps: [
                .report(neutralReport(), at: timestamp),
                .stop
            ])
            let result = try TrackpadRuntime.run(
                configuration: .default,
                observeOnly: false,
                stopToken: stopToken,
                dependencies: TrackpadRuntimeDependencies(
                    openHID: { hid },
                    makeOutput: { RecordingOutput() },
                    uptimeNanoseconds: { clock.now }
                )
            )

            XCTAssertEqual(result.summary.reportCount, 1)
        }
    }

    func testPublicStopTokenClearsAPriorStopRequestWhenAReuseBegins() throws {
        let stopToken = TrackpadStopToken()
        let firstClock = ManualUptimeClock()
        let firstHID = ScriptedHID(clock: firstClock, steps: [
            .perform { stopToken.requestStop() },
            .report(neutralReport(), at: 10)
        ])
        let firstResult = try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { firstHID },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { firstClock.now }
            )
        )
        XCTAssertEqual(firstResult.summary.reportCount, 0)

        let secondClock = ManualUptimeClock()
        let secondHID = ScriptedHID(clock: secondClock, steps: [
            .report(neutralReport(), at: 20),
            .stop
        ])
        let secondResult = try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { secondHID },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { secondClock.now }
            )
        )

        XCTAssertEqual(secondResult.summary.reportCount, 1)
    }

    func testPublicStopTokenPreservesAStopQueuedBeforeItsFirstRun() throws {
        let stopToken = TrackpadStopToken()
        stopToken.requestStop()
        let clock = ManualUptimeClock()
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 10)
        ])

        let result = try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { hid },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { clock.now }
            )
        )

        XCTAssertEqual(result.summary.reportCount, 0)
    }

    func testPublicStopTokenPreservesAStopQueuedBetweenRuns() throws {
        let stopToken = TrackpadStopToken()
        let firstClock = ManualUptimeClock()
        let firstHID = ScriptedHID(clock: firstClock, steps: [.stop])
        _ = try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { firstHID },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { firstClock.now }
            )
        )

        stopToken.requestStop()
        let secondClock = ManualUptimeClock()
        let secondHID = ScriptedHID(clock: secondClock, steps: [
            .report(neutralReport(), at: 20)
        ])
        let secondResult = try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { secondHID },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { secondClock.now }
            )
        )

        XCTAssertEqual(secondResult.summary.reportCount, 0)
    }

    func testPublicStopTokenReuseRejectsAnUnresolvedPriorLedgerWithoutOpeningHID() throws {
        let stopToken = TrackpadStopToken()
        let firstClock = ManualUptimeClock()
        let firstHID = ScriptedHID(clock: firstClock, steps: [
            .report(neutralReport(), at: 0),
            .report(heldLeftReport(), at: 10),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        configuration.left.dpadKeys.up = "space"

        XCTAssertThrowsError(try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { firstHID },
                makeOutput: { FailingReleaseOutput() },
                uptimeNanoseconds: { firstClock.now }
            )
        ))

        let secondClock = ManualUptimeClock()
        let secondHID = ScriptedHID(clock: secondClock, steps: [.stop])
        let openCount = Mutex(0)
        XCTAssertThrowsError(try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: {
                    openCount.withLock { $0 += 1 }
                    return secondHID
                },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { secondClock.now }
            )
        )) { error in
            XCTAssertTrue(String(describing: error).contains("before reusing the stop token"))
        }
        XCTAssertEqual(openCount.withLock { $0 }, 0)
    }

    func testRearPendingReleaseBlocksReplacementWithoutOpeningHID() throws {
        let stopToken = TrackpadStopToken()
        let firstClock = ManualUptimeClock()
        let firstHID = ScriptedHID(clock: firstClock, steps: [
            .report(neutralReport(), at: 0),
            .report(rearReport(0x20000), at: 10),
            .stop
        ])
        var configuration = PaddrConfiguration.default
        configuration.rearButtons.l4 = "f1"

        XCTAssertThrowsError(try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: { firstHID },
                makeOutput: { FailingReleaseOutput() },
                uptimeNanoseconds: { firstClock.now }
            )
        ))

        let secondClock = ManualUptimeClock()
        let secondHID = ScriptedHID(clock: secondClock, steps: [.stop])
        let openCount = Mutex(0)
        XCTAssertThrowsError(try TrackpadRuntime.run(
            configuration: .default,
            observeOnly: false,
            stopToken: stopToken,
            dependencies: TrackpadRuntimeDependencies(
                openHID: {
                    openCount.withLock { $0 += 1 }
                    return secondHID
                },
                makeOutput: { RecordingOutput() },
                uptimeNanoseconds: { secondClock.now }
            )
        )) { error in
            XCTAssertTrue(String(describing: error).contains("before reusing the stop token"))
        }
        XCTAssertEqual(openCount.withLock { $0 }, 0)
    }

    func testRearDuplicateOwnershipWithPadAndObserveOnly() throws {
        for observeOnly in [false, true] {
            for binding in ["space", "mouse-left"] {
                let clock = ManualUptimeClock()
                let output = RecordingOutput()
                var config = PaddrConfiguration.default
                config.left.mode = .dpad
                config.left.dpadKeys.up = binding
                config.rearButtons = .init(l4: binding, l5: binding == "space" ? "code:49" : binding)
                let hid = ScriptedHID(clock: clock, steps: [
                    .report(neutralReport(), at: 0),
                    .report(rearReport(0x20000), at: 10),
                    .report(rearReport(0x60000, padHeld: true), at: 20),
                    .report(rearReport(0x60000, padHeld: true), at: 30),
                    .report(rearReport(0x40000, padHeld: true), at: 40),
                    .report(rearReport(0x40000), at: 50),
                    .report(neutralReport(), at: 60)
                ])
                let result = try run(configuration: config, observeOnly: observeOnly, hid: hid,
                                     clock: clock, output: output, events: EventRecorder())
                XCTAssertEqual(result.summary.actionCount, 2)
                if observeOnly {
                    XCTAssertTrue(output.actions.isEmpty)
                } else if binding == "space" {
                    XCTAssertEqual(output.actions.count, 2)
                    XCTAssertEqual(output.actions.first, .key(try KeyCatalog.resolve("space"), isPressed: true))
                    XCTAssertEqual(output.actions.last, .key(try KeyCatalog.resolve("code:49"), isPressed: false))
                } else {
                    XCTAssertEqual(output.actions, [.mouseButton(.left, isPressed: true), .mouseButton(.left, isPressed: false)])
                }
            }
        }
    }

    func testAssignedRearNeutralGateAndUnassignedGrip() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        let gate = OutputGate()
        var config = PaddrConfiguration.default
        config.rearButtons.l4 = "f1"
        let hid = ScriptedHID(clock: clock, steps: [
            .report(rearReport(0x20000), at: 0), // assigned initial hold blocks
            .report(rearReport(0x100), at: 10), // unassigned R5 does not block
            .report(rearReport(0x20100), at: 20),
            .perform { gate.setEnabled(false) }, .wake(at: 30),
            .perform { gate.setEnabled(true) },
            .report(rearReport(0x20100), at: 40), // held across gate cannot resume
            .report(rearReport(0x100), at: 50),
            .report(rearReport(0x20100), at: 60), .stop
        ])
        _ = try run(configuration: config, outputGate: gate, hid: hid, clock: clock, output: output, events: events)
        let f1 = try KeyCatalog.resolve("f1")
        XCTAssertEqual(output.actions, [.key(f1, isPressed: true), .key(f1, isPressed: false),
                                        .key(f1, isPressed: true), .key(f1, isPressed: false)])
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 2)
    }

    func testRearHoldsReleaseOnEveryLossBoundaryAndRetryFailedRelease() throws {
        let endings: [[ScriptedHID.Step]] = [
            [.stop], [.remove], [.report([0x46, 1], at: 20)],
            [.wake(at: 1_000_000_010)],
            [.delayedReport(neutralReport(), receivedAt: 20, processedAt: 1_000_000_020)]
        ]
        for ending in endings {
            let clock = ManualUptimeClock()
            let output = FailOnceReleaseOutput()
            var config = PaddrConfiguration.default
            config.rearButtons = .init(l4: "f1", l5: "f2", r4: "mouse-left", r5: "mouse-right")
            let hid = ScriptedHID(clock: clock, steps: [
                .report(neutralReport(), at: 0), .report(rearReport(0x60180), at: 10)
            ] + ending)
            _ = try run(configuration: config, hid: hid, clock: clock, output: output, events: EventRecorder())
            XCTAssertEqual(output.committed.filter { !$0.isReleaseForTesting }.count, 4)
            XCTAssertEqual(output.committed.filter(\.isReleaseForTesting).count, 4)
            XCTAssertEqual(output.attempts.filter(\.isReleaseForTesting).count, 5)
        }
    }

    func testRearPartialPostFailureReleasesOnlyCommittedPress() throws {
        let clock = ManualUptimeClock()
        let output = FailingCallOutput(failingCalls: [2])
        var config = PaddrConfiguration.default
        config.rearButtons = .init(l4: "f1", l5: "f2")
        let hid = ScriptedHID(clock: clock, steps: [.report(neutralReport(), at: 0), .report(rearReport(0x60000), at: 10)])
        XCTAssertThrowsError(try run(configuration: config, hid: hid, clock: clock, output: output, events: EventRecorder()))
        let f1 = try KeyCatalog.resolve("f1")
        XCTAssertEqual(output.committed, [.key(f1, isPressed: true), .key(f1, isPressed: false)])
    }

    func testExpiredNeutralAndPressCannotRearmAndFreshNeutralRecovers() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let events = EventRecorder()
        var config = PaddrConfiguration.default
        config.rearButtons.l4 = "f1"
        let hid = ScriptedHID(clock: clock, steps: [
            .report(neutralReport(), at: 0), .report(rearReport(0x20000), at: 10),
            .delayedReport(neutralReport(), receivedAt: 20, processedAt: 1_000_000_020),
            .delayedReport(rearReport(0x20000), receivedAt: 30, processedAt: 1_000_000_030),
            .report(rearReport(0x20000), at: 1_000_000_040),
            .report(neutralReport(), at: 1_000_000_050),
            .report(rearReport(0x20000), at: 1_000_000_060), .stop
        ])
        let result = try run(configuration: config, hid: hid, clock: clock, output: output, events: events)
        XCTAssertEqual(result.summary.reportCount, 5)
        XCTAssertEqual(result.summary.actionCount, 2)
        let f1 = try KeyCatalog.resolve("f1")
        XCTAssertEqual(output.actions, [.key(f1, isPressed: true), .key(f1, isPressed: false),
                                        .key(f1, isPressed: true), .key(f1, isPressed: false)])
        XCTAssertEqual(events.events.filter { $0 == .outputArmed }.count, 2)
    }

    func testRuntimeChecksStopAndDurationInsideTransportBatch() throws {
        for stopByToken in [false, true] {
            let clock = ManualUptimeClock()
            let token = TrackpadStopToken()
            let output = RecordingOutput { action in
                if !action.isReleaseForTesting {
                    if stopByToken { token.requestStop() } else { clock.set(100) }
                }
            }
            var config = PaddrConfiguration.default
            config.rearButtons = .init(l4: "f1", l5: "f2")
            let hid = UncheckedBatchHID(reports: [neutralReport(), rearReport(0x20000), rearReport(0x60000)])
            _ = try TrackpadRuntime.run(configuration: config, observeOnly: false, stopToken: token,
                duration: stopByToken ? nil : .nanoseconds(100), dependencies: .init(
                    openHID: { hid }, makeOutput: { output }, uptimeNanoseconds: { clock.now }))
            let f1 = try KeyCatalog.resolve("f1")
            XCTAssertEqual(output.actions, [.key(f1, isPressed: true), .key(f1, isPressed: false)])
        }
    }

    func testRearConfigurationReplacementReleasesOldBindingAndRequiresNeutral() throws {
        let clock = ManualUptimeClock()
        let token = TrackpadStopToken()
        let output = RecordingOutput()
        for binding in ["f1", "f2"] {
            var config = PaddrConfiguration.default
            config.rearButtons.l4 = binding
            let hid = ScriptedHID(clock: clock, steps: [
                .report(rearReport(0x20000), at: 0), .report(neutralReport(), at: 10),
                .report(rearReport(0x20000), at: 20), .stop
            ])
            _ = try TrackpadRuntime.run(configuration: config, observeOnly: false, stopToken: token,
                dependencies: .init(openHID: { hid }, makeOutput: { output }, uptimeNanoseconds: { clock.now }))
        }
        XCTAssertEqual(output.actions, [
            .key(try KeyCatalog.resolve("f1"), isPressed: true), .key(try KeyCatalog.resolve("f1"), isPressed: false),
            .key(try KeyCatalog.resolve("f2"), isPressed: true), .key(try KeyCatalog.resolve("f2"), isPressed: false)
        ])
    }

    func testScrollResidualIsClearedAcrossGateAndControllerEpochs() throws {
        for gateReset in [false, true] {
            let clock = ManualUptimeClock()
            let gate = OutputGate()
            let output = RecordingOutput()
            var config = PaddrConfiguration.default
            config.left.scrollSensitivity = 0.5
            let reset: [ScriptedHID.Step] = gateReset
                ? [.perform { gate.setEnabled(false) }, .wake(at: 30), .perform { gate.setEnabled(true) }]
                : [.report([0x46, 1], at: 30)]
            let hid = ScriptedHID(clock: clock, steps: [
                .report(neutralReport(), at: 0),
                .report(report(leftTouched: true, rightTouched: false, leftX: 0), at: 10),
                .report(report(leftTouched: true, rightTouched: false, leftX: 360), at: 20)
            ] + reset + [
                .report(neutralReport(), at: 40),
                .report(report(leftTouched: true, rightTouched: false, leftX: 0), at: 50),
                .report(report(leftTouched: true, rightTouched: false, leftX: 120), at: 60), .stop
            ])
            _ = try run(configuration: config, outputGate: gate, hid: hid, clock: clock,
                        output: output, events: EventRecorder())
            XCTAssertTrue(output.actions.isEmpty)
        }
    }

    func testObserveOnlyRearDiagnosticsAndFreshnessBoundary() throws {
        let clock = ManualUptimeClock()
        let output = RecordingOutput()
        let diagnostics = StringRecorder()
        var config = PaddrConfiguration.default
        config.rearButtons.r4 = "f3"
        let hid = ScriptedHID(clock: clock, steps: [
            .delayedReport(neutralReport(), receivedAt: 0, processedAt: 999_999_999),
            .delayedReport(rearReport(0x80), receivedAt: 1, processedAt: 1_000_000_000),
            .delayedReport(neutralReport(), receivedAt: 2, processedAt: 1_000_000_001)
        ])
        let result = try TrackpadRuntime.run(configuration: config, observeOnly: true, stopToken: TrackpadStopToken(),
            dependencies: .init(openHID: { hid }, makeOutput: { output }, uptimeNanoseconds: { clock.now }),
            onAction: diagnostics.append)
        XCTAssertEqual(result.summary.actionCount, 2)
        XCTAssertEqual(diagnostics.values, ["key f3 down", "key f3 up"])
        XCTAssertTrue(output.actions.isEmpty)
    }

    private func run(
        configuration: PaddrConfiguration = .default,
        observeOnly: Bool = false,
        outputGate: OutputGate? = nil,
        duration: Duration? = nil,
        hid: ScriptedHID,
        clock: ManualUptimeClock,
        output: any TrackpadOutputDispatching = RecordingOutput(),
        events: EventRecorder
    ) throws -> TrackpadRunResult {
        try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: observeOnly,
            outputGate: outputGate,
            stopToken: TrackpadStopToken(),
            duration: duration,
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
        case slotReport(Int, [UInt8], at: UInt64)
        case delayedReport([UInt8], receivedAt: UInt64, processedAt: UInt64)
        case wake(at: UInt64)
        case perform(@Sendable () -> Void)
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
        onReport: (TrackpadHIDReport) throws -> Void
    ) throws -> TrackpadStreamTermination {
        for step in steps {
            guard shouldContinue() else { return .stopped }
            switch step {
            case let .report(bytes, uptime):
                clock.set(uptime)
                try onReport(TrackpadHIDReport(slot: 0, bytes: bytes, timestampNanoseconds: uptime))
            case let .slotReport(slot, bytes, uptime):
                clock.set(uptime)
                try onReport(TrackpadHIDReport(slot: slot, bytes: bytes, timestampNanoseconds: uptime))
            case let .delayedReport(bytes, receivedAt, processedAt):
                clock.set(processedAt)
                try onReport(TrackpadHIDReport(slot: 0, bytes: bytes, timestampNanoseconds: receivedAt))
            case let .wake(uptime):
                clock.set(uptime)
                try onWake()
            case let .perform(action):
                action()
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

private final class StringRecorder: Sendable {
    private let storage = Mutex<[String]>([])
    var values: [String] { storage.withLock { $0 } }
    func append(_ value: String) { storage.withLock { $0.append(value) } }
}

private final class FailingCallOutput: TrackpadOutputDispatching, Sendable {
    private struct State: ~Copyable {
        var callCount = 0
        var failingCalls: Set<Int>
        var attempts: [TrackpadOutputAction] = []
        var committed: [TrackpadOutputAction] = []
    }

    private let state: Mutex<State>

    init(failingCalls: Set<Int>) {
        state = Mutex(State(failingCalls: failingCalls))
    }

    var attempts: [TrackpadOutputAction] { state.withLock { $0.attempts } }
    var committed: [TrackpadOutputAction] { state.withLock { $0.committed } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions {
            try state.withLock { state in
                state.callCount += 1
                state.attempts.append(action)
                if state.failingCalls.remove(state.callCount) != nil {
                    throw PaddrError.output("Injected output failure.")
                }
                state.committed.append(action)
            }
        }
    }
}

private final class FailOnceReleaseOutput: TrackpadOutputDispatching, Sendable {
    private struct State: ~Copyable {
        var failedRelease = false
        var attempts: [TrackpadOutputAction] = []
        var committed: [TrackpadOutputAction] = []
    }

    private let state = Mutex(State())
    var attempts: [TrackpadOutputAction] { state.withLock { $0.attempts } }
    var committed: [TrackpadOutputAction] { state.withLock { $0.committed } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions {
            try state.withLock { state in
                state.attempts.append(action)
                if action.isReleaseForTesting, !state.failedRelease {
                    state.failedRelease = true
                    throw PaddrError.output("Injected one-time release failure.")
                }
                state.committed.append(action)
            }
        }
    }
}

private final class FailingReleaseOutput: TrackpadOutputDispatching, Sendable {
    private let releaseStorage = Mutex<[TrackpadOutputAction]>([])
    var releaseAttempts: [TrackpadOutputAction] { releaseStorage.withLock { $0 } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions where action.isReleaseForTesting {
            releaseStorage.withLock { $0.append(action) }
            throw PaddrError.output("Injected release failure.")
        }
    }
}

private func outputReleasedEvents(in events: [TrackpadSessionEvent]) -> [TrackpadSessionEvent] {
    events.filter { event in
        if case .outputReleased = event { return true }
        return false
    }
}

private func neutralReport() -> [UInt8] {
    report(leftTouched: false, rightTouched: false)
}

private func heldLeftReport() -> [UInt8] {
    report(leftTouched: true, rightTouched: false)
}

private func batteryReport(chargeState: UInt8, percentage: UInt8) -> [UInt8] {
    [0x43, chargeState, percentage] + [UInt8](repeating: 0, count: 12)
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

private func rearReport(_ bits: UInt32, padHeld: Bool = false) -> [UInt8] {
    var bytes = report(leftTouched: padHeld, rightTouched: false)
    for offset in 0..<4 { bytes[2 + offset] |= UInt8(truncatingIfNeeded: bits >> (8 * offset)) }
    return bytes
}

private struct UncheckedBatchHID: TrackpadHIDStreaming {
    let reports: [[UInt8]]
    let summaryDescription = "Unchecked batch fixture"
    func stream(shouldContinue: () -> Bool, onWake: () throws -> Void,
                onReport: (TrackpadHIDReport) throws -> Void) throws -> TrackpadStreamTermination {
        guard shouldContinue() else { return .stopped }
        for bytes in reports { try onReport(.init(slot: 0, bytes: bytes, timestampNanoseconds: 0)) }
        return .stopped
    }
}
