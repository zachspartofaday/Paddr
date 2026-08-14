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

public final class OutputGate: Sendable {
    private let enabled: Mutex<Bool>

    public init(enabled: Bool = true) {
        self.enabled = Mutex(enabled)
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled.withLock { $0 = enabled }
    }

    public var isEnabled: Bool {
        enabled.withLock { $0 }
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
    case waitingForController(String)
    case controllerConnected
    case outputArmed
    case outputReleased
    case progress(TrackpadRunSummary)
    case controllerLost(TrackpadRunSummary)
    case stopped(TrackpadRunSummary)
    case receiverRemoved(TrackpadRunSummary)
    case receiverUnavailable(String)
    case failed(String)
}

public protocol TrackpadSessionControlling: Sendable {
    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent>
    func stop() async
}

public struct TrackpadRuntimeDependencies: Sendable {
    public var openHID: @Sendable () throws -> any TrackpadHIDStreaming
    public var makeOutput: @Sendable () -> any TrackpadOutputDispatching
    public var wallNow: @Sendable () -> Date
    public var uptimeNanoseconds: @Sendable () -> UInt64

    public init(
        openHID: @escaping @Sendable () throws -> any TrackpadHIDStreaming,
        makeOutput: @escaping @Sendable () -> any TrackpadOutputDispatching,
        wallNow: @escaping @Sendable () -> Date = Date.init,
        uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.openHID = openHID
        self.makeOutput = makeOutput
        self.wallNow = wallNow
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    public static let live = TrackpadRuntimeDependencies(
        openHID: { try TritonHIDDevice.open() },
        makeOutput: { CGEventOutput() }
    )
}

public enum TrackpadRuntime {
    static let controllerLossDeadlineNanoseconds: UInt64 = 1_000_000_000

    public static func run(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate? = nil,
        stopToken: TrackpadStopToken,
        deadline: Date? = nil,
        dependencies: TrackpadRuntimeDependencies = .live,
        onEvent: (@Sendable (TrackpadSessionEvent) -> Void)? = nil,
        onAction: (@Sendable (String) -> Void)? = nil
    ) throws -> TrackpadRunResult {
        let validated = try configuration.validated()
        let device = try dependencies.openHID()
        let output = dependencies.makeOutput()
        var controllerEpoch: ControllerEpoch?
        var controllerLive = false
        var lastAcceptedReportUptime: UInt64?
        var outputWasEnabled = outputGate?.isEnabled ?? true
        var reportCount = 0
        var actionCount = 0

        func summary() -> TrackpadRunSummary {
            TrackpadRunSummary(reportCount: reportCount, actionCount: actionCount)
        }

        func releaseEpochOutputs() throws {
            guard var epoch = controllerEpoch else { return }
            controllerEpoch = nil

            var cleanupFailures: [String] = []
            let leftReleases: [TrackpadOutputAction]
            do {
                leftReleases = try epoch.leftMapper.releaseAll()
            } catch {
                leftReleases = []
                cleanupFailures.append("left-pad release mapping failed: \(error)")
            }
            let rightReleases: [TrackpadOutputAction]
            do {
                rightReleases = try epoch.rightMapper.releaseAll()
            } catch {
                rightReleases = []
                cleanupFailures.append("right-pad release mapping failed: \(error)")
            }
            let releases = epoch.arbiter.process(leftReleases, from: .leftPad)
                + epoch.arbiter.process(rightReleases, from: .rightPad)
                + epoch.arbiter.releaseAll()
            if !observeOnly {
                for release in releases {
                    do {
                        try output.dispatch([release])
                    } catch {
                        cleanupFailures.append("\(release.description): \(error)")
                    }
                }
            }
            if !cleanupFailures.isEmpty {
                throw TrackIsBackError.output(
                    "Could not release held outputs: \(cleanupFailures.joined(separator: "; "))."
                )
            }
        }

        func loseControllerIfDeadlineReached(at uptime: UInt64) throws {
            guard let lastAccepted = lastAcceptedReportUptime,
                  uptime >= lastAccepted,
                  uptime - lastAccepted >= controllerLossDeadlineNanoseconds
            else { return }
            lastAcceptedReportUptime = nil
            controllerLive = false
            try releaseEpochOutputs()
            onEvent?(.controllerLost(summary()))
        }

        func reconcileOutputGate() throws {
            let outputIsEnabled = outputGate?.isEnabled ?? true
            guard outputIsEnabled != outputWasEnabled else { return }
            outputWasEnabled = outputIsEnabled
            guard !outputIsEnabled else { return }
            try releaseEpochOutputs()
            onEvent?(.outputReleased)
        }

        onEvent?(.waitingForController(device.summaryDescription))
        if outputGate != nil, !outputWasEnabled {
            onEvent?(.outputReleased)
        }
        let streamOutcome: Result<TrackpadStreamTermination, any Error>
        do {
            streamOutcome = .success(try device.stream(
                shouldContinue: {
                    stopToken.shouldContinue && (deadline.map { dependencies.wallNow() < $0 } ?? true)
                },
                onWake: {
                    try reconcileOutputGate()
                    try loseControllerIfDeadlineReached(at: dependencies.uptimeNanoseconds())
                },
                onReport: { bytes, timestamp in
                    guard let pads = TritonParser.parseTrackpads(bytes, timestampNanoseconds: timestamp) else {
                        return
                    }
                    try loseControllerIfDeadlineReached(at: timestamp)
                    lastAcceptedReportUptime = timestamp
                    reportCount += 1

                    if !controllerLive {
                        controllerLive = true
                        onEvent?(.controllerConnected)
                    }
                    try reconcileOutputGate()
                    guard outputWasEnabled else {
                        if reportCount.isMultiple(of: 100) { onEvent?(.progress(summary())) }
                        return
                    }

                    if controllerEpoch == nil {
                        controllerEpoch = ControllerEpoch(configuration: validated)
                    }
                    guard var epoch = controllerEpoch else { return }

                    if !epoch.isArmed {
                        guard pads.isNeutral else {
                            controllerEpoch = epoch
                            return
                        }
                        _ = try epoch.leftMapper.process(pads.left)
                        _ = try epoch.rightMapper.process(pads.right)
                        epoch.isArmed = true
                        controllerEpoch = epoch
                        onEvent?(.outputArmed)
                        if reportCount.isMultiple(of: 100) { onEvent?(.progress(summary())) }
                        return
                    }

                    let left = try epoch.leftMapper.process(pads.left)
                    let right = try epoch.rightMapper.process(pads.right)
                    let actions = epoch.arbiter.process(left, from: .leftPad)
                        + epoch.arbiter.process(right, from: .rightPad)
                    controllerEpoch = epoch
                    actionCount += actions.count
                    for action in actions { onAction?(action.description) }
                    if !observeOnly { try output.dispatch(actions) }
                    if reportCount.isMultiple(of: 100) { onEvent?(.progress(summary())) }
                }
            ))
        } catch {
            streamOutcome = .failure(error)
        }

        do {
            try releaseEpochOutputs()
        } catch {
            let streamFailure: String
            switch streamOutcome {
            case .success:
                streamFailure = ""
            case let .failure(runtimeError):
                streamFailure = " Runtime also failed: \(runtimeError)."
            }
            throw TrackIsBackError.output("\(error)\(streamFailure)")
        }

        return TrackpadRunResult(
            summary: summary(),
            termination: try streamOutcome.get()
        )
    }
}

private struct ControllerEpoch {
    var leftMapper: PadMapper
    var rightMapper: PadMapper
    var arbiter = OutputArbiter()
    var isArmed = false

    init(configuration: TrackIsBackConfiguration) {
        leftMapper = PadMapper(side: .left, configuration: configuration.left)
        rightMapper = PadMapper(side: .right, configuration: configuration.right)
    }
}

private extension TrackpadPair {
    var isNeutral: Bool {
        !left.isTouched && !left.isClicked && !right.isTouched && !right.isClicked
    }
}

public actor TrackpadSession: TrackpadSessionControlling {
    public typealias Runtime = @Sendable (
        TrackIsBackConfiguration,
        Bool,
        OutputGate?,
        TrackpadStopToken,
        @escaping @Sendable (TrackpadSessionEvent) -> Void
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
        observeOnly: Bool = false,
        outputGate: OutputGate? = nil
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
        let eventBuffer = SessionEventBuffer(continuation: continuation)
        eventBuffer.yield(.connecting)
        let runtime = self.runtime
        let eventGate = self.eventGate

        let task = Task.detached(priority: .userInitiated) {
            let outcome = Result {
                try runtime(
                    configuration,
                    observeOnly,
                    outputGate,
                    token,
                    { event in
                        eventGate.enqueue(ifCurrent: request) {
                            eventBuffer.yield(event)
                        }
                    }
                )
            }
            let delivered = eventGate.enqueue(ifCurrent: request) {
                switch outcome {
                case let .success(result):
                    switch result.termination {
                    case .stopped: eventBuffer.yield(.stopped(result.summary))
                    case .deviceRemoved: eventBuffer.yield(.receiverRemoved(result.summary))
                    }
                case let .failure(error as TrackIsBackError):
                    if case .device = error {
                        eventBuffer.yield(.receiverUnavailable(error.description))
                    } else {
                        eventBuffer.yield(.failed(error.description))
                    }
                case let .failure(error):
                    eventBuffer.yield(.failed(String(describing: error)))
                }
                eventBuffer.finish()
            }
            if !delivered { eventBuffer.finish() }
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
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        onEvent: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: observeOnly,
            outputGate: outputGate,
            stopToken: stopToken,
            onEvent: onEvent
        )
    }
}

private final class SessionEventBuffer: Sendable {
    private let continuation: AsyncStream<TrackpadSessionEvent>.Continuation
    private let controllerSnapshot = Mutex<[TrackpadSessionEvent]>([.connecting])

    init(continuation: AsyncStream<TrackpadSessionEvent>.Continuation) {
        self.continuation = continuation
    }

    func yield(_ event: TrackpadSessionEvent) {
        let recoveryEvents = controllerSnapshot.withLock { snapshot in
            switch event {
            case .connecting:
                snapshot = [.connecting]
            case let .waitingForController(description):
                snapshot = [.waitingForController(description)]
            case .controllerConnected:
                snapshot = [.controllerConnected]
            case .outputArmed:
                snapshot = [.controllerConnected, .outputArmed]
            case .outputReleased:
                if snapshot.last != .outputReleased {
                    snapshot = snapshot.filter { $0 != .outputArmed } + [.outputReleased]
                }
            case let .controllerLost(summary):
                snapshot = [.controllerLost(summary)]
            case .progress:
                break
            case .stopped, .receiverRemoved, .receiverUnavailable, .failed:
                snapshot = []
            }
            return snapshot
        }

        guard case let .dropped(droppedEvent) = continuation.yield(event),
              droppedEvent.isControllerState,
              !recoveryEvents.isEmpty
        else { return }
        for recoveryEvent in recoveryEvents {
            continuation.yield(recoveryEvent)
        }
    }

    func finish() {
        continuation.finish()
    }
}

private extension TrackpadSessionEvent {
    var isControllerState: Bool {
        switch self {
        case .connecting, .waitingForController, .controllerConnected, .outputArmed,
             .outputReleased, .controllerLost:
            true
        case .progress, .stopped, .receiverRemoved, .receiverUnavailable, .failed:
            false
        }
    }
}

final class SessionEventGate: Sendable {
    private let generation = Mutex<UInt64>(0)

    func activate(_ value: UInt64) {
        generation.withLock { $0 = value }
    }

    @discardableResult
    func enqueue(ifCurrent value: UInt64, _ operation: () -> Void) -> Bool {
        generation.withLock { current in
            guard current == value else { return false }
            operation()
            return true
        }
    }
}
