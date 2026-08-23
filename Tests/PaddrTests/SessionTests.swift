import Synchronization
import XCTest
@testable import PaddrCore

final class SessionTests: XCTestCase {
    func testConcurrentStartsLaunchOnlyLatestReplacement() async {
        let runtime = GatedRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        _ = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)

        let firstConfiguration = configuration(sensitivity: 2)
        let firstReplacement = Task { await session.start(configuration: firstConfiguration) }
        await waitForEpoch(2, session: session)
        let latestConfiguration = configuration(sensitivity: 3)
        let latestReplacement = Task { await session.start(configuration: latestConfiguration) }
        await waitForEpoch(3, session: session)

        runtime.release(worker: 1)
        let supersededStream = await firstReplacement.value
        _ = await latestReplacement.value
        await runtime.waitForStartCount(2)

        let supersededEvents = await events(in: supersededStream)
        XCTAssertEqual(supersededEvents, [])
        XCTAssertEqual(runtime.sensitivities, [1, 3])
        XCTAssertEqual(runtime.maximumConcurrent, 1)

        let stop = Task { _ = await session.stop() }
        await waitForEpoch(4, session: session)
        runtime.release(worker: 2)
        await stop.value
        XCTAssertEqual(runtime.activeCount, 0)
    }

    func testStartStopStartKeepsEveryWorkerReachable() async {
        let runtime = GatedRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        _ = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)

        let replacementConfiguration = configuration(sensitivity: 2)
        let replacement = Task { await session.start(configuration: replacementConfiguration) }
        await waitForEpoch(2, session: session)
        let stop = Task { _ = await session.stop() }
        await waitForEpoch(3, session: session)
        let latestConfiguration = configuration(sensitivity: 4)
        let latest = Task { await session.start(configuration: latestConfiguration) }
        await waitForEpoch(4, session: session)

        runtime.release(worker: 1)
        let replacementStream = await replacement.value
        let replacementEvents = await events(in: replacementStream)
        XCTAssertEqual(replacementEvents, [])
        await stop.value
        _ = await latest.value
        await runtime.waitForStartCount(2)

        XCTAssertEqual(runtime.sensitivities, [1, 4])
        XCTAssertEqual(runtime.maximumConcurrent, 1)
        let finalStop = Task { _ = await session.stop() }
        await waitForEpoch(5, session: session)
        runtime.release(worker: 2)
        await finalStop.value
        XCTAssertEqual(runtime.activeCount, 0)
    }

    func testCancelledReplacementDoesNotLaunch() async {
        let runtime = GatedRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        _ = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)

        let replacementConfiguration = configuration(sensitivity: 9)
        let replacement = Task { await session.start(configuration: replacementConfiguration) }
        await waitForEpoch(2, session: session)
        replacement.cancel()
        runtime.release(worker: 1)

        let replacementStream = await replacement.value
        let replacementEvents = await events(in: replacementStream)
        XCTAssertEqual(replacementEvents, [])
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.activeCount, 0)
        await session.stop()
    }

    func testOldWorkerFinishesBeforeReplacementCanProduceOutput() async {
        let runtime = GatedRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        let oldStream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)

        let replacementConfiguration = configuration(sensitivity: 2)
        let replacement = Task { await session.start(configuration: replacementConfiguration) }
        await waitForEpoch(2, session: session)
        runtime.release(worker: 1)
        _ = await replacement.value
        await runtime.waitForStartCount(2)

        let oldEvents = await events(in: oldStream)
        XCTAssertEqual(Array(runtime.lifecycleEvents.prefix(3)), ["start:1", "finish:1", "start:2"])
        XCTAssertEqual(oldEvents.filter { $0 == .controllerConnected }.count, 1)
        XCTAssertFalse(oldEvents.contains(.controllerLost(.init(reportCount: 1, actionCount: 1))))
        XCTAssertEqual(runtime.maximumConcurrent, 1)

        let stop = Task { _ = await session.stop() }
        await waitForEpoch(3, session: session)
        runtime.release(worker: 2)
        await stop.value
    }

    func testSupersededStreamSuffixIsEmptyAcrossLateDeliveryBranches() async {
        let runtime = GatedRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        let oldStream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)
        let oldEvents = SessionEventProbe<TrackpadSessionEvent>()
        let observation = oldEvents.observe(oldStream)
        await oldEvents.wait { events, _ in events.count >= 3 }
        XCTAssertEqual(
            Array(oldEvents.events.prefix(3)),
            [.connecting, .waitingForController("worker:1"), .controllerConnected]
        )

        let replacementConfiguration = configuration(sensitivity: 2)
        let replacement = Task {
            await session.start(configuration: replacementConfiguration)
        }
        await waitForEpoch(2, session: session)
        runtime.release(worker: 1)
        _ = await replacement.value
        await runtime.waitForStartCount(2)

        await finish(observation, after: oldEvents)
        XCTAssertEqual(Array(oldEvents.events.dropFirst(3)), [])

        let stop = Task { _ = await session.stop() }
        await waitForEpoch(3, session: session)
        runtime.release(worker: 2)
        await stop.value
    }

    func testControllerStateSurvivesProgressPressureAndTerminalFinishesStream() async {
        let runtime = ProgressPressureRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        let stream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitUntilProduced()
        let events = SessionEventProbe<TrackpadSessionEvent>()
        let observation = events.observe(stream)
        await events.wait { values, _ in values.count >= 32 }
        let bufferedEvents = Array(events.events.prefix(32))

        let connectedIndex = bufferedEvents.firstIndex(of: .controllerConnected)
        let armedIndex = bufferedEvents.lastIndex(of: .outputArmed)
        XCTAssertNotNil(connectedIndex)
        XCTAssertNotNil(armedIndex)
        if let connectedIndex, let armedIndex {
            XCTAssertLessThan(connectedIndex, armedIndex)
        }
        XCTAssertEqual(
            bufferedEvents.compactMap { event -> TrackpadRunSummary? in
                guard case let .progress(summary) = event else { return nil }
                return summary
            }.last,
            .init(reportCount: 80, actionCount: 8)
        )
        XCTAssertLessThanOrEqual(bufferedEvents.count, 32)

        runtime.release()
        await finish(observation, after: events)
        XCTAssertEqual(
            Array(events.events.dropFirst(32)),
            [.stopped(.init(reportCount: 80, actionCount: 8))]
        )
        await session.stop()
    }

    func testReleaseAcknowledgementSurvivesProgressPressure() async {
        let runtime = ReleasePressureRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        let stream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitUntilProduced()
        let events = SessionEventProbe<TrackpadSessionEvent>()
        let observation = events.observe(stream)
        await events.wait { values, _ in values.count >= 32 }
        let bufferedEvents = Array(events.events.prefix(32))

        XCTAssertTrue(bufferedEvents.contains(.outputReleased(revision: 7)))
        XCTAssertTrue(bufferedEvents.contains(.controllerConnected))

        runtime.release()
        await finish(observation, after: events)
        _ = await session.stop()
    }

    func testLatestBatterySnapshotIsCoalescedAndRecoveredUnderProgressPressure() async {
        let runtime = BatteryPressureRuntime(losesController: false)
        let session = TrackpadSession(runtime: runtime.run)
        let stream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitUntilProduced()
        let events = SessionEventProbe<TrackpadSessionEvent>()
        let observation = events.observe(stream)
        await events.wait { values, _ in values.count >= 32 }
        let bufferedEvents = Array(events.events.prefix(32))

        let recoveredBatteryValues = bufferedEvents.compactMap { event -> ControllerBatteryStatus? in
            guard case let .batteryUpdated(battery) = event else { return nil }
            return battery
        }
        XCTAssertFalse(recoveredBatteryValues.isEmpty)
        XCTAssertTrue(
            recoveredBatteryValues.allSatisfy {
                $0 == .init(chargeState: .charging, percentage: 82)
            }
        )
        XCTAssertEqual(
            bufferedEvents.compactMap { event -> TrackpadRunSummary? in
                guard case let .progress(summary) = event else { return nil }
                return summary
            }.last,
            .init(reportCount: 80, actionCount: 0)
        )
        XCTAssertLessThanOrEqual(bufferedEvents.count, 32)

        runtime.release()
        await finish(observation, after: events)
        XCTAssertEqual(
            Array(events.events.dropFirst(32)),
            [.stopped(.init(reportCount: 80, actionCount: 0))]
        )
        _ = await session.stop()
    }

    func testControllerLossClearsRecoverableBatterySnapshotUnderProgressPressure() async {
        let runtime = BatteryPressureRuntime(losesController: true)
        let session = TrackpadSession(runtime: runtime.run)
        let stream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitUntilProduced()
        let events = SessionEventProbe<TrackpadSessionEvent>()
        let observation = events.observe(stream)
        await events.wait { values, _ in values.count >= 32 }
        let bufferedEvents = Array(events.events.prefix(32))

        XCTAssertFalse(bufferedEvents.contains { event in
            if case .batteryUpdated = event { return true }
            return false
        })
        XCTAssertTrue(bufferedEvents.contains(.controllerLost(.init(reportCount: 2, actionCount: 0))))
        XCTAssertEqual(
            bufferedEvents.compactMap { event -> TrackpadRunSummary? in
                guard case let .progress(summary) = event else { return nil }
                return summary
            }.last,
            .init(reportCount: 80, actionCount: 0)
        )
        XCTAssertLessThanOrEqual(bufferedEvents.count, 32)

        runtime.release()
        await finish(observation, after: events)
        _ = await session.stop()
    }

    func testEventGateRejectsEnqueueFromSupersededGeneration() {
        let gate = SessionEventGate()
        var delivered: [String] = []
        gate.activate(1)

        XCTAssertTrue(gate.enqueue(ifCurrent: 1) { delivered.append("current") })
        gate.activate(2)
        XCTAssertFalse(gate.enqueue(ifCurrent: 1) { delivered.append("stale") })
        XCTAssertEqual(delivered, ["current"])
    }

    func testStopTreatsDeviceErrorsAsCleanTeardown() async {
        let session = TrackpadSession { _, _, _, stopToken, _ in
            while stopToken.shouldContinue {}
            throw PaddrError.device("No Steam Controller 2 puck interface was found.")
        }
        _ = await session.start(configuration: configuration(sensitivity: 1))
        let outcome = await session.stop()
        XCTAssertEqual(outcome, .clean)
    }

    func testStopReportsWorkerTeardownFailure() async {
        let session = TrackpadSession { _, _, _, stopToken, _ in
            while stopToken.shouldContinue {}
            throw PaddrError.output("Could not release held outputs: injected.")
        }
        _ = await session.start(configuration: configuration(sensitivity: 1))
        let outcome = await session.stop()
        guard case let .failed(diagnostic) = outcome else {
            return XCTFail("Expected the teardown failure to propagate through stop()")
        }
        XCTAssertTrue(diagnostic.contains("Could not release held outputs"))
    }

    func testPendingPhysicalReleaseBlocksReplacementUntilLaterRetryDrainsIt() async throws {
        let space = try KeyCatalog.resolve("space")
        let output = ToggleReleaseOutput()
        let runtime = RetainedLedgerRuntime(output: output, key: space)
        let session = TrackpadSession(runtime: runtime.run)

        let firstStream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)

        let blockedStream = await session.start(configuration: configuration(sensitivity: 2))
        let blockedEvents = await events(in: blockedStream)
        XCTAssertEqual(blockedEvents.count, 1)
        guard case let .failed(diagnostic) = blockedEvents.first else {
            return XCTFail("Expected replacement to fail closed while a physical hold remains")
        }
        XCTAssertTrue(diagnostic.contains("pending key space up"))
        XCTAssertEqual(runtime.startCount, 1)
        let firstEvents = await events(in: firstStream)
        XCTAssertEqual(firstEvents, [.connecting])

        let repeatedStop = await session.stop()
        guard case .failed = repeatedStop else {
            return XCTFail("Expected repeated stop to keep reporting the persistent release failure")
        }

        output.allowReleases()
        let replacementStream = await session.start(configuration: configuration(sensitivity: 3))
        await runtime.waitForStartCount(2)
        XCTAssertEqual(runtime.startCount, 2)

        let finalOutcome = await session.stop()
        XCTAssertEqual(finalOutcome, .clean)
        let replacementEvents = await events(in: replacementStream)
        XCTAssertEqual(replacementEvents, [.connecting])
        XCTAssertEqual(output.committed, [
            .key(space, isPressed: true),
            .key(space, isPressed: false),
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    private func configuration(sensitivity: Double) -> PaddrConfiguration {
        var configuration = PaddrConfiguration.default
        configuration.left.sensitivity = sensitivity
        return configuration
    }

    private func events(
        in stream: AsyncStream<TrackpadSessionEvent>
    ) async -> [TrackpadSessionEvent] {
        let probe = SessionEventProbe<TrackpadSessionEvent>()
        let observation = probe.observe(stream)
        let didFinish = await probe.wait { _, isFinished in isFinished }
        if !didFinish { observation.cancel() }
        await observation.value
        return probe.events
    }

    private func finish<Event: Sendable>(
        _ observation: Task<Void, Never>,
        after probe: SessionEventProbe<Event>
    ) async {
        let didFinish = await probe.wait { _, isFinished in isFinished }
        if !didFinish { observation.cancel() }
        await observation.value
    }

    private func waitForEpoch(_ epoch: UInt64, session: TrackpadSession) async {
        await eventually { await session.requestEpochForTesting() >= epoch }
    }
}

private final class ProgressPressureRuntime: Sendable {
    private let produced = SessionEventProbe<Void>()
    private let releaseGate = BoundedTestGate()

    func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        event(.waitingForController("pressure-test"))
        event(.controllerConnected)
        event(.outputArmed)
        for reportCount in 1...40 {
            event(.progress(.init(reportCount: reportCount, actionCount: reportCount / 10)))
        }
        event(.controllerLost(.init(reportCount: 40, actionCount: 4)))
        event(.controllerConnected)
        event(.outputArmed)
        for reportCount in 41...80 {
            event(.progress(.init(reportCount: reportCount, actionCount: reportCount / 10)))
        }
        produced.record(())
        releaseGate.wait()
        return TrackpadRunResult(
            summary: .init(reportCount: 80, actionCount: 8),
            termination: .stopped
        )
    }

    func waitUntilProduced() async {
        await produced.wait { events, _ in !events.isEmpty }
    }

    func release() {
        releaseGate.signal()
    }
}

private final class ReleasePressureRuntime: Sendable {
    private let produced = SessionEventProbe<Void>()
    private let releaseGate = BoundedTestGate()

    func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        event(.waitingForController("release-pressure-test"))
        event(.outputReleased(revision: 7))
        event(.controllerConnected)
        for reportCount in 1...80 {
            event(.progress(.init(reportCount: reportCount, actionCount: 0)))
        }
        produced.record(())
        releaseGate.wait()
        return TrackpadRunResult(
            summary: .init(reportCount: 80, actionCount: 0),
            termination: .stopped
        )
    }

    func waitUntilProduced() async {
        await produced.wait { events, _ in !events.isEmpty }
    }

    func release() {
        releaseGate.signal()
    }
}

private final class BatteryPressureRuntime: Sendable {
    private let losesController: Bool
    private let produced = SessionEventProbe<Void>()
    private let releaseGate = BoundedTestGate()

    init(losesController: Bool) {
        self.losesController = losesController
    }

    func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        event(.waitingForController("battery-pressure-test"))
        event(.controllerConnected)
        event(.batteryUpdated(.init(chargeState: .discharging, percentage: 10)))
        event(.batteryUpdated(.init(chargeState: .charging, percentage: 82)))
        if losesController {
            event(.controllerLost(.init(reportCount: 2, actionCount: 0)))
        }
        for reportCount in 1...80 {
            event(.progress(.init(reportCount: reportCount, actionCount: 0)))
        }
        produced.record(())
        releaseGate.wait()
        return TrackpadRunResult(
            summary: .init(reportCount: 80, actionCount: 0),
            termination: .stopped
        )
    }

    func waitUntilProduced() async {
        await produced.wait { events, _ in !events.isEmpty }
    }

    func release() {
        releaseGate.signal()
    }
}

private final class GatedRuntime: Sendable {
    private struct State: ~Copyable {
        var nextID = 0
        var active = 0
        var maximum = 0
        var sensitivities: [Double] = []
        var lifecycleEvents: [String] = []
        var gates: [Int: BoundedTestGate] = [:]
    }

    private let state = Mutex(State())
    private let starts = SessionEventProbe<Int>()

    var startCount: Int { state.withLock { $0.nextID } }
    var activeCount: Int { state.withLock { $0.active } }
    var maximumConcurrent: Int { state.withLock { $0.maximum } }
    var sensitivities: [Double] { state.withLock { $0.sensitivities } }
    var lifecycleEvents: [String] { state.withLock { $0.lifecycleEvents } }

    func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        let (id, gate) = state.withLock { state -> (Int, BoundedTestGate) in
            state.nextID += 1
            let id = state.nextID
            let gate = BoundedTestGate()
            state.gates[id] = gate
            state.active += 1
            state.maximum = max(state.maximum, state.active)
            state.sensitivities.append(configuration.left.sensitivity)
            state.lifecycleEvents.append("start:\(id)")
            return (id, gate)
        }
        event(.waitingForController("worker:\(id)"))
        event(.controllerConnected)
        starts.record(id)
        gate.wait()
        event(.controllerConnected)
        event(.controllerLost(.init(reportCount: id, actionCount: id)))
        event(.progress(.init(reportCount: id, actionCount: id)))
        state.withLock {
            $0.active -= 1
            $0.lifecycleEvents.append("finish:\(id)")
            $0.gates[id] = nil
        }
        return TrackpadRunResult(
            summary: .init(reportCount: 0, actionCount: 0),
            termination: .stopped
        )
    }

    func release(worker id: Int) {
        state.withLock { $0.gates[id] }?.signal()
    }

    func waitForStartCount(_ expectedCount: Int) async {
        if startCount >= expectedCount { return }
        await starts.wait { events, _ in
            events.contains { $0 >= expectedCount }
        }
    }
}

private final class RetainedLedgerRuntime: Sendable {
    private let output: ToggleReleaseOutput
    private let key: KeyBinding
    private let starts: AsyncStream<Int>
    private let startContinuation: AsyncStream<Int>.Continuation
    private let count = Mutex(0)

    init(output: ToggleReleaseOutput, key: KeyBinding) {
        self.output = output
        self.key = key
        (starts, startContinuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
    }

    var startCount: Int { count.withLock { $0 } }

    func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        let ledger = HeldOutputLedger(output: output)
        try stopToken.beginRun(retaining: ledger)
        defer { stopToken.finishRun() }
        try ledger.dispatch([.key(key, isPressed: true)])
        let started = count.withLock { count in
            count += 1
            return count
        }
        startContinuation.yield(started)
        while stopToken.shouldContinue {}
        return TrackpadRunResult(
            summary: .init(reportCount: 0, actionCount: 1),
            termination: .stopped
        )
    }

    func waitForStartCount(_ expectedCount: Int) async {
        if startCount >= expectedCount { return }
        var iterator = starts.makeAsyncIterator()
        while let count = await iterator.next() {
            if count >= expectedCount { return }
        }
    }
}

private final class ToggleReleaseOutput: TrackpadOutputDispatching, Sendable {
    private struct State: ~Copyable {
        var releasesAllowed = false
        var committed: [TrackpadOutputAction] = []
    }

    private let state = Mutex(State())
    var committed: [TrackpadOutputAction] { state.withLock { $0.committed } }

    func allowReleases() {
        state.withLock { $0.releasesAllowed = true }
    }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions {
            try state.withLock { state in
                switch action {
                case let .key(_, isPressed), let .mouseButton(_, isPressed):
                    if !isPressed, !state.releasesAllowed {
                        throw PaddrError.output("Injected persistent release failure.")
                    }
                case .mouseMove, .scroll:
                    break
                }
                state.committed.append(action)
            }
        }
    }
}
