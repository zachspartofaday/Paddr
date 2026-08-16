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

public struct OutputGateSnapshot: Equatable, Sendable {
    public let isEnabled: Bool
    public let revision: UInt64

    public init(isEnabled: Bool, revision: UInt64) {
        self.isEnabled = isEnabled
        self.revision = revision
    }
}

public final class OutputGate: Sendable {
    private struct State: ~Copyable {
        var isEnabled: Bool
        var revision: UInt64 = 0
    }

    private let state: Mutex<State>

    public init(enabled: Bool = true) {
        state = Mutex(State(isEnabled: enabled))
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> UInt64 {
        state.withLock { state in
            state.isEnabled = enabled
            state.revision &+= 1
            return state.revision
        }
    }

    public var isEnabled: Bool {
        state.withLock { $0.isEnabled }
    }

    public var snapshot: OutputGateSnapshot {
        state.withLock { OutputGateSnapshot(isEnabled: $0.isEnabled, revision: $0.revision) }
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
    case batteryUpdated(ControllerBatteryStatus)
    case outputArmed
    case outputReleased(revision: UInt64)
    case progress(TrackpadRunSummary)
    case controllerLost(TrackpadRunSummary)
    case stopped(TrackpadRunSummary)
    case receiverRemoved(TrackpadRunSummary)
    case receiverUnavailable(String)
    case failed(String)
}

public enum TrackpadSessionStopOutcome: Equatable, Sendable {
    case clean
    case failed(String)
}

public protocol TrackpadSessionControlling: Sendable {
    func start(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent>
    @discardableResult
    func stop() async -> TrackpadSessionStopOutcome
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
        configuration: PaddrConfiguration,
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
        // The dongle carries one controller slot per interface; Paddr drives one controller,
        // so the first slot with evidence is adopted and other slots are ignored until loss.
        var activeSlot: Int?
        var observedGate = outputGate?.snapshot ?? OutputGateSnapshot(isEnabled: true, revision: 0)
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
                throw PaddrError.output(
                    "Could not release held outputs: \(cleanupFailures.joined(separator: "; "))."
                )
            }
        }

        func loseController() throws {
            activeSlot = nil
            lastAcceptedReportUptime = nil
            controllerLive = false
            try releaseEpochOutputs()
            onEvent?(.controllerLost(summary()))
        }

        func loseControllerIfDeadlineReached(at uptime: UInt64) throws {
            guard let lastAccepted = lastAcceptedReportUptime,
                  uptime >= lastAccepted,
                  uptime - lastAccepted >= controllerLossDeadlineNanoseconds
            else { return }
            try loseController()
        }

        func reconcileOutputGate() throws {
            guard let outputGate else { return }
            let current = outputGate.snapshot
            guard current.revision != observedGate.revision else { return }
            observedGate = current
            guard !current.isEnabled else { return }
            try releaseEpochOutputs()
            onEvent?(.outputReleased(revision: current.revision))
        }

        onEvent?(.waitingForController(device.summaryDescription))
        if outputGate != nil, !observedGate.isEnabled {
            onEvent?(.outputReleased(revision: observedGate.revision))
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
                onReport: { report in
                    let bytes = report.bytes
                    let timestamp = report.timestampNanoseconds
                    if let wirelessConnected = TritonParser.parseWirelessConnection(bytes) {
                        if wirelessConnected {
                            if let activeSlot, activeSlot != report.slot { return }
                            try loseControllerIfDeadlineReached(at: timestamp)
                            activeSlot = report.slot
                            lastAcceptedReportUptime = timestamp
                            if !controllerLive {
                                controllerLive = true
                                onEvent?(.controllerConnected)
                            }
                        } else if controllerLive, activeSlot == report.slot {
                            try loseController()
                        }
                        return
                    }
                    if let battery = TritonParser.parseBatteryStatus(bytes) {
                        guard activeSlot == report.slot else { return }
                        try loseControllerIfDeadlineReached(at: timestamp)
                        guard controllerLive, activeSlot == report.slot else { return }
                        onEvent?(.batteryUpdated(battery))
                        return
                    }
                    guard let pads = TritonParser.parseTrackpads(bytes, timestampNanoseconds: timestamp) else {
                        return
                    }
                    if let activeSlot, activeSlot != report.slot { return }
                    try loseControllerIfDeadlineReached(at: timestamp)
                    activeSlot = report.slot
                    lastAcceptedReportUptime = timestamp
                    reportCount += 1

                    if !controllerLive {
                        controllerLive = true
                        onEvent?(.controllerConnected)
                    }
                    try reconcileOutputGate()
                    guard observedGate.isEnabled else {
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
            throw PaddrError.output("\(error)\(streamFailure)")
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

    init(configuration: PaddrConfiguration) {
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
        PaddrConfiguration,
        Bool,
        OutputGate?,
        TrackpadStopToken,
        @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult

    private struct WorkerRecord: Sendable {
        let id: UInt64
        let stopToken: TrackpadStopToken
        let task: Task<TrackpadSessionStopOutcome, Never>
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
        configuration: PaddrConfiguration,
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

        let task = Task.detached(priority: .userInitiated) { () -> TrackpadSessionStopOutcome in
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
                case let .failure(error as PaddrError):
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
            switch outcome {
            case .success:
                return .clean
            case let .failure(error as PaddrError):
                if case .output = error {
                    return .failed(error.description)
                }
                return .clean
            case let .failure(error):
                return .failed(String(describing: error))
            }
        }
        activeWorker = WorkerRecord(id: request, stopToken: token, task: task)
        continuation.onTermination = { @Sendable [weak token] _ in token?.requestStop() }
        return stream
    }

    @discardableResult
    public func stop() async -> TrackpadSessionStopOutcome {
        advanceRequestEpoch()
        eventGate.activate(requestEpoch)
        return await teardownActiveWorker()
    }

    @discardableResult
    private func teardownActiveWorker() async -> TrackpadSessionStopOutcome {
        guard let worker = activeWorker else { return .clean }
        worker.stopToken.requestStop()
        let outcome = await worker.task.value
        if activeWorker?.id == worker.id {
            activeWorker = nil
        }
        return outcome
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
        configuration: PaddrConfiguration,
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
                snapshot = preservingReleaseAcknowledgement(
                    base: [.waitingForController(description)],
                    from: snapshot
                )
            case .controllerConnected:
                snapshot = preservingReleaseAcknowledgement(
                    base: [.controllerConnected] + latestBatterySnapshot(in: snapshot),
                    from: snapshot
                )
            case let .batteryUpdated(battery):
                snapshot.removeAll { $0.isBatteryUpdate }
                snapshot.append(.batteryUpdated(battery))
            case .outputArmed:
                snapshot = [.controllerConnected, .outputArmed] + latestBatterySnapshot(in: snapshot)
            case let .outputReleased(revision):
                snapshot = snapshot.filter { event in
                    switch event {
                    case .outputArmed, .outputReleased: false
                    default: true
                    }
                } + [.outputReleased(revision: revision)]
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

private func preservingReleaseAcknowledgement(
    base: [TrackpadSessionEvent],
    from snapshot: [TrackpadSessionEvent]
) -> [TrackpadSessionEvent] {
    guard let acknowledgement = snapshot.last(where: { event in
        if case .outputReleased = event { return true }
        return false
    }) else { return base }
    return base + [acknowledgement]
}

private func latestBatterySnapshot(in snapshot: [TrackpadSessionEvent]) -> [TrackpadSessionEvent] {
    snapshot.last(where: \.isBatteryUpdate).map { [$0] } ?? []
}

private extension TrackpadSessionEvent {
    var isBatteryUpdate: Bool {
        if case .batteryUpdated = self { return true }
        return false
    }

    var isControllerState: Bool {
        switch self {
        case .connecting, .waitingForController, .controllerConnected, .batteryUpdated,
             .outputArmed, .outputReleased, .controllerLost:
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
