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
        XCTAssertEqual(oldEvents.filter { $0 == .controllerConnected }.count, 1)
        XCTAssertFalse(oldEvents.contains(.controllerLost(.init(reportCount: 1, actionCount: 1))))
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
        let initialEvents = [await oldIterator.next(), await oldIterator.next(), await oldIterator.next()]
        XCTAssertEqual(initialEvents, [.connecting, .waitingForController("worker:1"), .controllerConnected])

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

    func testControllerStateSurvivesProgressPressureAndTerminalFinishesStream() async {
        let runtime = ProgressPressureRuntime()
        let session = TrackpadSession(runtime: runtime.run)
        let stream = await session.start(configuration: configuration(sensitivity: 1))
        await runtime.waitUntilProduced()

        var iterator = stream.makeAsyncIterator()
        var bufferedEvents: [TrackpadSessionEvent] = []
        for _ in 0..<32 {
            guard let event = await iterator.next() else {
                return XCTFail("Expected the bounded session buffer to remain open")
            }
            bufferedEvents.append(event)
        }

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
        var suffix: [TrackpadSessionEvent] = []
        while let event = await iterator.next() { suffix.append(event) }
        XCTAssertEqual(suffix, [.stopped(.init(reportCount: 80, actionCount: 8))])
        await session.stop()
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

private final class ProgressPressureRuntime: Sendable {
    private let produced: AsyncStream<Void>
    private let producedContinuation: AsyncStream<Void>.Continuation
    private let releaseGate = DispatchSemaphore(value: 0)

    init() {
        (produced, producedContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func run(
        configuration: TrackIsBackConfiguration,
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
        producedContinuation.yield(())
        releaseGate.wait()
        return TrackpadRunResult(
            summary: .init(reportCount: 80, actionCount: 8),
            termination: .stopped
        )
    }

    func waitUntilProduced() async {
        var iterator = produced.makeAsyncIterator()
        _ = await iterator.next()
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
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
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
        event(.waitingForController("worker:\(id)"))
        event(.controllerConnected)
        startContinuation.yield(id)
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
        var iterator = starts.makeAsyncIterator()
        while let count = await iterator.next() {
            if count >= expectedCount { return }
        }
    }
}
