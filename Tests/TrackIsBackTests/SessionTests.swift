import Dispatch
import Synchronization
import XCTest
@testable import TrackIsBackCore

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

        let stop = Task { await session.stop() }
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
        let stop = Task { await session.stop() }
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
        let finalStop = Task { await session.stop() }
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
        XCTAssertFalse(oldEvents.contains(.connected("late:1")))
        XCTAssertEqual(runtime.maximumConcurrent, 1)

        let stop = Task { await session.stop() }
        await waitForEpoch(3, session: session)
        runtime.release(worker: 2)
        await stop.value
    }

    func testSupersededStreamSuffixIsEmptyAcrossLateDeliveryBranches() async {
        let runtime = GatedRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        let oldStream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitForStartCount(1)
        var oldIterator = oldStream.makeAsyncIterator()
        let initialEvents = [await oldIterator.next(), await oldIterator.next()]
        XCTAssertEqual(initialEvents, [.connecting, .connected("worker:1")])

        let replacementConfiguration = configuration(sensitivity: 2)
        let replacement = Task {
            await session.start(configuration: replacementConfiguration)
        }
        await waitForEpoch(2, session: session)
        runtime.release(worker: 1)
        _ = await replacement.value
        await runtime.waitForStartCount(2)

        var supersededEvents: [TrackpadSessionEvent] = []
        while let event = await oldIterator.next() { supersededEvents.append(event) }
        XCTAssertEqual(supersededEvents, [])

        let stop = Task { await session.stop() }
        await waitForEpoch(3, session: session)
        runtime.release(worker: 2)
        await stop.value
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

    private func configuration(sensitivity: Double) -> TrackIsBackConfiguration {
        var configuration = TrackIsBackConfiguration.default
        configuration.left.sensitivity = sensitivity
        return configuration
    }

    private func events(
        in stream: AsyncStream<TrackpadSessionEvent>
    ) async -> [TrackpadSessionEvent] {
        var result: [TrackpadSessionEvent] = []
        for await event in stream { result.append(event) }
        return result
    }

    private func waitForEpoch(_ epoch: UInt64, session: TrackpadSession) async {
        await session.waitForRequestEpochForTesting(epoch)
    }
}

private final class GatedRuntime: Sendable {
    private struct State: ~Copyable {
        var nextID = 0
        var active = 0
        var maximum = 0
        var sensitivities: [Double] = []
        var lifecycleEvents: [String] = []
        var gates: [Int: DispatchSemaphore] = [:]
    }

    private let state = Mutex(State())
    private let starts: AsyncStream<Int>
    private let startContinuation: AsyncStream<Int>.Continuation

    init() {
        (starts, startContinuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
    }

    var startCount: Int { state.withLock { $0.nextID } }
    var activeCount: Int { state.withLock { $0.active } }
    var maximumConcurrent: Int { state.withLock { $0.maximum } }
    var sensitivities: [Double] { state.withLock { $0.sensitivities } }
    var lifecycleEvents: [String] { state.withLock { $0.lifecycleEvents } }

    func run(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        stopToken: TrackpadStopToken,
        connected: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (TrackpadRunSummary) -> Void
    ) throws -> TrackpadRunResult {
        let (id, gate) = state.withLock { state -> (Int, DispatchSemaphore) in
            state.nextID += 1
            let id = state.nextID
            let gate = DispatchSemaphore(value: 0)
            state.gates[id] = gate
            state.active += 1
            state.maximum = max(state.maximum, state.active)
            state.sensitivities.append(configuration.left.sensitivity)
            state.lifecycleEvents.append("start:\(id)")
            return (id, gate)
        }
        connected("worker:\(id)")
        startContinuation.yield(id)
        gate.wait()
        connected("late:\(id)")
        progress(.init(reportCount: id, actionCount: id))
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
        var iterator = starts.makeAsyncIterator()
        while let count = await iterator.next() {
            if count >= expectedCount { return }
        }
    }
}
