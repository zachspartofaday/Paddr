import Foundation
import Synchronization

public final class TrackpadStopToken: Sendable {
    private let stopped = Mutex(false)

    public init() {}

    public func requestStop() {
        stopped.withLock { $0 = true }
    }

    public var shouldContinue: Bool {
        stopped.withLock { !$0 }
    }
}

public struct TrackpadRunSummary: Equatable, Sendable {
    public let reportCount: Int
    public let actionCount: Int

    public init(reportCount: Int, actionCount: Int) {
        self.reportCount = reportCount
        self.actionCount = actionCount
    }
}

public struct TrackpadRunResult: Equatable, Sendable {
    public let summary: TrackpadRunSummary
    public let termination: TrackpadStreamTermination

    public init(summary: TrackpadRunSummary, termination: TrackpadStreamTermination) {
        self.summary = summary
        self.termination = termination
    }
}

public enum TrackpadSessionEvent: Equatable, Sendable {
    case connecting
    case connected(String)
    case progress(TrackpadRunSummary)
    case stopped(TrackpadRunSummary)
    case deviceRemoved(TrackpadRunSummary)
    case deviceUnavailable(String)
    case failed(String)
}

public protocol TrackpadSessionControlling: Sendable {
    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool
    ) async -> AsyncStream<TrackpadSessionEvent>
    func stop() async
}

public struct TrackpadRuntimeDependencies: Sendable {
    public var openHID: @Sendable () throws -> any TrackpadHIDStreaming
    public var makeOutput: @Sendable () -> any TrackpadOutputDispatching
    public var now: @Sendable () -> Date

    public init(
        openHID: @escaping @Sendable () throws -> any TrackpadHIDStreaming,
        makeOutput: @escaping @Sendable () -> any TrackpadOutputDispatching,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.openHID = openHID
        self.makeOutput = makeOutput
        self.now = now
    }

    public static let live = TrackpadRuntimeDependencies(
        openHID: { try TritonHIDDevice.open() },
        makeOutput: { CGEventOutput() }
    )
}

public enum TrackpadRuntime {
    public static func run(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        stopToken: TrackpadStopToken,
        deadline: Date? = nil,
        dependencies: TrackpadRuntimeDependencies = .live,
        onConnected: (@Sendable (String) -> Void)? = nil,
        onAction: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (TrackpadRunSummary) -> Void)? = nil
    ) throws -> TrackpadRunResult {
        let validated = try configuration.validated()
        let device = try dependencies.openHID()
        onConnected?(device.summaryDescription)
        var leftMapper = PadMapper(side: .left, configuration: validated.left)
        var rightMapper = PadMapper(side: .right, configuration: validated.right)
        var arbiter = OutputArbiter()
        let output = dependencies.makeOutput()
        var reportCount = 0
        var actionCount = 0

        defer {
            let leftReleases = (try? leftMapper.releaseAll()) ?? []
            let rightReleases = (try? rightMapper.releaseAll()) ?? []
            let releases = arbiter.process(leftReleases, from: .leftPad)
                + arbiter.process(rightReleases, from: .rightPad)
                + arbiter.releaseAll()
            if !observeOnly { try? output.dispatch(releases) }
        }

        let termination = try device.stream(
            shouldContinue: {
                stopToken.shouldContinue && (deadline.map { dependencies.now() < $0 } ?? true)
            },
            onReport: { bytes, timestamp in
                guard let pads = TritonParser.parseTrackpads(bytes, timestampNanoseconds: timestamp) else { return }
                reportCount += 1
                let left = try leftMapper.process(pads.left)
                let right = try rightMapper.process(pads.right)
                let actions = arbiter.process(left, from: .leftPad)
                    + arbiter.process(right, from: .rightPad)
                actionCount += actions.count
                for action in actions { onAction?(action.description) }
                if !observeOnly { try output.dispatch(actions) }
                if reportCount.isMultiple(of: 100) {
                    onProgress?(TrackpadRunSummary(reportCount: reportCount, actionCount: actionCount))
                }
            }
        )
        return TrackpadRunResult(
            summary: TrackpadRunSummary(reportCount: reportCount, actionCount: actionCount),
            termination: termination
        )
    }
}

public actor TrackpadSession: TrackpadSessionControlling {
    public typealias Runtime = @Sendable (
        TrackIsBackConfiguration,
        Bool,
        TrackpadStopToken,
        @escaping @Sendable (String) -> Void,
        @escaping @Sendable (TrackpadRunSummary) -> Void
    ) throws -> TrackpadRunResult

    private struct WorkerRecord: Sendable {
        let id: UInt64
        let stopToken: TrackpadStopToken
        let task: Task<Void, Never>
    }

    private let runtime: Runtime
    private let eventGate = SessionEventGate()
    private var activeWorker: WorkerRecord?
    private var requestEpoch: UInt64 = 0
    #if DEBUG
    private var epochWaiters: [(epoch: UInt64, continuation: CheckedContinuation<Void, Never>)] = []
    #endif

    public init(runtime: @escaping Runtime = TrackpadSession.liveRuntime) {
        self.runtime = runtime
    }

    public func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool = false
    ) async -> AsyncStream<TrackpadSessionEvent> {
        advanceRequestEpoch()
        let request = requestEpoch
        eventGate.activate(request)
        await teardownActiveWorker()

        guard request == requestEpoch, !Task.isCancelled else {
            return Self.finishedEventStream()
        }

        let token = TrackpadStopToken()
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        continuation.yield(.connecting)
        let runtime = self.runtime
        let eventGate = self.eventGate

        let task = Task.detached(priority: .userInitiated) {
            let outcome = Result {
                try runtime(
                    configuration,
                    observeOnly,
                    token,
                    { description in
                        if eventGate.isCurrent(request) {
                            continuation.yield(.connected(description))
                        }
                    },
                    { summary in
                        if eventGate.isCurrent(request) {
                            continuation.yield(.progress(summary))
                        }
                    }
                )
            }
            guard eventGate.isCurrent(request) else {
                continuation.finish()
                return
            }
            switch outcome {
            case let .success(result):
                switch result.termination {
                case .stopped: continuation.yield(.stopped(result.summary))
                case .deviceRemoved: continuation.yield(.deviceRemoved(result.summary))
                }
            case let .failure(error as TrackIsBackError):
                if case .device = error {
                    continuation.yield(.deviceUnavailable(error.description))
                } else {
                    continuation.yield(.failed(error.description))
                }
            case let .failure(error):
                continuation.yield(.failed(String(describing: error)))
            }
            continuation.finish()
        }
        activeWorker = WorkerRecord(id: request, stopToken: token, task: task)
        continuation.onTermination = { @Sendable [weak token] _ in token?.requestStop() }
        return stream
    }

    public func stop() async {
        advanceRequestEpoch()
        eventGate.activate(requestEpoch)
        await teardownActiveWorker()
    }

    private func teardownActiveWorker() async {
        guard let worker = activeWorker else { return }
        worker.stopToken.requestStop()
        await worker.task.value
        if activeWorker?.id == worker.id {
            activeWorker = nil
        }
    }

    private static func finishedEventStream() -> AsyncStream<TrackpadSessionEvent> {
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        continuation.finish()
        return stream
    }

    #if DEBUG
    func waitForRequestEpochForTesting(_ expectedEpoch: UInt64) async {
        guard requestEpoch < expectedEpoch else { return }
        await withCheckedContinuation { continuation in
            epochWaiters.append((expectedEpoch, continuation))
        }
    }
    #endif

    private func advanceRequestEpoch() {
        requestEpoch &+= 1
        #if DEBUG
        let ready = epochWaiters.filter { $0.epoch <= requestEpoch }
        epochWaiters.removeAll { $0.epoch <= requestEpoch }
        for waiter in ready { waiter.continuation.resume() }
        #endif
    }

    public static func liveRuntime(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        stopToken: TrackpadStopToken,
        onConnected: @escaping @Sendable (String) -> Void,
        onProgress: @escaping @Sendable (TrackpadRunSummary) -> Void
    ) throws -> TrackpadRunResult {
        try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: observeOnly,
            stopToken: stopToken,
            onConnected: onConnected,
            onProgress: onProgress
        )
    }
}

private final class SessionEventGate: Sendable {
    private let generation = Mutex<UInt64>(0)

    func activate(_ value: UInt64) {
        generation.withLock { $0 = value }
    }

    func isCurrent(_ value: UInt64) -> Bool {
        generation.withLock { $0 == value }
    }
}
