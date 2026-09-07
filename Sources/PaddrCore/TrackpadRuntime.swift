import Dispatch
import Synchronization

public final class TrackpadStopToken: Sendable {
    private struct State: ~Copyable {
        var nextStopGeneration: UInt64 = 0
        var pendingStopGeneration: UInt64?
        var consumedStopGeneration: UInt64?
        var outputLedger: HeldOutputLedger?
        var hasActiveRun = false
    }

    private let state = Mutex(State())

    public init() {}

    public func requestStop() {
        state.withLock { state in
            state.nextStopGeneration &+= 1
            state.pendingStopGeneration = state.nextStopGeneration
        }
    }

    public var shouldContinue: Bool {
        state.withLock { state in
            guard let pendingStopGeneration = state.pendingStopGeneration else { return true }
            if state.hasActiveRun {
                state.consumedStopGeneration = pendingStopGeneration
            }
            return false
        }
    }

    func beginRun(retaining ledger: HeldOutputLedger) throws {
        let priorLedger: HeldOutputLedger? = try state.withLock { state in
            guard !state.hasActiveRun else {
                throw PaddrError.output("The stop token is already attached to an active run.")
            }
            state.hasActiveRun = true
            state.consumedStopGeneration = nil
            return state.outputLedger
        }

        do {
            if let priorLedger {
                let releaseAttempt = priorLedger.releasePending(maxPasses: 2)
                guard releaseAttempt.isDrained else {
                    throw PaddrError.output(
                        "Could not release held outputs before reusing the stop token: "
                            + "\(releaseAttempt.diagnostic)."
                    )
                }
            }
            state.withLock { $0.outputLedger = ledger }
        } catch {
            state.withLock { $0.hasActiveRun = false }
            throw error
        }
    }

    func finishRun() {
        state.withLock { state in
            if state.pendingStopGeneration == state.consumedStopGeneration {
                state.pendingStopGeneration = nil
            }
            state.consumedStopGeneration = nil
            state.hasActiveRun = false
        }
    }

    var hasPendingOutputs: Bool {
        retainedOutputLedger?.pendingOutputs.isEmpty == false
    }

    func releasePendingOutputs(maxPasses: Int) -> OutputReleaseAttempt? {
        retainedOutputLedger?.releasePending(maxPasses: maxPasses)
    }

    private var retainedOutputLedger: HeldOutputLedger? {
        state.withLock { $0.outputLedger }
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
    /// A held key or mouse button still requires its matching physical release event.
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
    public var uptimeNanoseconds: @Sendable () -> UInt64

    public init(
        openHID: @escaping @Sendable () throws -> any TrackpadHIDStreaming,
        makeOutput: @escaping @Sendable () -> any TrackpadOutputDispatching,
        uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.openHID = openHID
        self.makeOutput = makeOutput
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    public static let live = TrackpadRuntimeDependencies(
        openHID: { try TritonHIDDevice.open() },
        makeOutput: { CGEventOutput() }
    )
}

private struct MonotonicRunLimit: Sendable {
    let startedAt: UInt64
    let durationNanoseconds: UInt64

    func permits(_ uptime: UInt64) -> Bool {
        guard uptime >= startedAt else { return false }
        return uptime - startedAt < durationNanoseconds
    }
}

public enum TrackpadRuntime {
    static let controllerLossDeadlineNanoseconds: UInt64 = 1_000_000_000

    package static func validatedDurationNanoseconds(_ duration: Duration) throws -> UInt64 {
        let components = duration.components
        guard duration > .zero,
              components.seconds >= 0,
              components.attoseconds >= 0
        else {
            throw PaddrError.configuration("--duration must be positive.")
        }

        let (wholeNanoseconds, wholeOverflow) = UInt64(components.seconds)
            .multipliedReportingOverflow(by: 1_000_000_000)
        guard !wholeOverflow else {
            throw PaddrError.configuration("--duration is too large.")
        }
        let fractionalNanoseconds = (UInt64(components.attoseconds) + 999_999_999)
            / 1_000_000_000
        let (nanoseconds, additionOverflow) = wholeNanoseconds
            .addingReportingOverflow(fractionalNanoseconds)
        guard !additionOverflow, nanoseconds > 0 else {
            throw PaddrError.configuration("--duration is too large.")
        }
        return nanoseconds
    }

    public static func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate? = nil,
        stopToken: TrackpadStopToken,
        duration: Duration? = nil,
        dependencies: TrackpadRuntimeDependencies = .live,
        onEvent: (@Sendable (TrackpadSessionEvent) -> Void)? = nil,
        onAction: (@Sendable (String) -> Void)? = nil
    ) throws -> TrackpadRunResult {
        let validated = try configuration.validated()
        let runLimit = try duration.map {
            MonotonicRunLimit(
                startedAt: dependencies.uptimeNanoseconds(),
                durationNanoseconds: try validatedDurationNanoseconds($0)
            )
        }
        let output = HeldOutputLedger(output: dependencies.makeOutput())
        try stopToken.beginRun(retaining: output)
        defer { stopToken.finishRun() }
        let device = try dependencies.openHID()
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
            let epochToRelease = controllerEpoch
            controllerEpoch = nil

            var mappingFailures: [String] = []
            var dispatchFailures: [String] = []
            if var epoch = epochToRelease {
                let leftReleases: [TrackpadOutputAction]
                do {
                    leftReleases = try epoch.leftMapper.releaseAll()
                } catch {
                    leftReleases = []
                    mappingFailures.append("left-pad release mapping failed: \(error)")
                }
                let rightReleases: [TrackpadOutputAction]
                do {
                    rightReleases = try epoch.rightMapper.releaseAll()
                } catch {
                    rightReleases = []
                    mappingFailures.append("right-pad release mapping failed: \(error)")
                }
                let releases = epoch.arbiter.process(leftReleases, from: .leftPad)
                    + epoch.arbiter.process(rightReleases, from: .rightPad)
                    + epoch.arbiter.releaseAll()
                for release in releases {
                    guard !observeOnly else { continue }
                    do {
                        try output.dispatch([release])
                    } catch {
                        dispatchFailures.append("\(release.description): \(error)")
                    }
                }
            }

            let releaseAttempt = output.releasePending(maxPasses: 2)
            guard releaseAttempt.isDrained, mappingFailures.isEmpty else {
                var cleanupFailures = mappingFailures
                if !releaseAttempt.isDrained {
                    cleanupFailures.append(contentsOf: dispatchFailures)
                    cleanupFailures.append(releaseAttempt.diagnostic)
                }
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
                    stopToken.shouldContinue
                        && (runLimit.map { $0.permits(dependencies.uptimeNanoseconds()) } ?? true)
                },
                onWake: {
                    try reconcileOutputGate()
                    try loseControllerIfDeadlineReached(at: dependencies.uptimeNanoseconds())
                },
                onReport: { report in
                    let now = dependencies.uptimeNanoseconds()
                    guard stopToken.shouldContinue,
                          runLimit.map({ $0.permits(now) }) ?? true else { return }
                    let bytes = report.bytes
                    let timestamp = report.timestampNanoseconds
                    // Queued input cannot renew liveness or re-arm a new epoch after expiry.
                    guard now >= timestamp,
                          now - timestamp < controllerLossDeadlineNanoseconds else {
                        if controllerLive, activeSlot == report.slot { try loseController() }
                        return
                    }
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
                    guard let state = TritonParser.parseControllerState(bytes, timestampNanoseconds: timestamp) else {
                        return
                    }
                    let pads = state.pads
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
                        controllerEpoch = try ControllerEpoch(configuration: validated)
                    }
                    guard var epoch = controllerEpoch else { return }

                    if !epoch.isArmed {
                        guard pads.isNeutral, epoch.rearMapper.isNeutral(state.rearButtons) else {
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
                    var actions = epoch.arbiter.process(left, from: .leftPad)
                        + epoch.arbiter.process(right, from: .rightPad)
                    for (source, action) in epoch.rearMapper.process(state.rearButtons) {
                        actions += epoch.arbiter.process([action], from: source)
                    }
                    if !observeOnly { try output.dispatch(actions) }
                    controllerEpoch = epoch
                    actionCount += actions.count
                    for action in actions { onAction?(action.description) }
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
    var rearMapper: RearButtonMapper
    var arbiter = OutputArbiter()
    var isArmed = false

    init(configuration: PaddrConfiguration) throws {
        leftMapper = PadMapper(side: .left, configuration: configuration.left)
        rightMapper = PadMapper(side: .right, configuration: configuration.right)
        rearMapper = try RearButtonMapper(configuration: configuration.rearButtons)
    }
}

// One logical owner per physical button preserves duplicate key/mouse bindings.
private struct RearButtonMapper {
    private var bindings: [RearButton: HeldOutput] = [:]
    private var previous = TritonRearButtonState()

    init(configuration: RearButtonConfiguration) throws {
        for button in RearButton.allCases {
            guard let binding = configuration[button] else { continue }
            switch binding {
            case TapBindingCatalog.leftMouseButton: bindings[button] = .mouseButton(.left)
            case TapBindingCatalog.rightMouseButton: bindings[button] = .mouseButton(.right)
            default: bindings[button] = .key(try KeyCatalog.resolve(binding))
            }
        }
    }

    func isNeutral(_ state: TritonRearButtonState) -> Bool {
        bindings.keys.allSatisfy { !state.isPressed($0) }
    }

    mutating func process(_ state: TritonRearButtonState) -> [(OutputSource, TrackpadOutputAction)] {
        defer { previous = state }
        return RearButton.allCases.compactMap { button in
            guard let binding = bindings[button],
                  state.isPressed(button) != previous.isPressed(button) else { return nil }
            let source: OutputSource
            switch button {
            case .l4: source = .rearL4
            case .l5: source = .rearL5
            case .r4: source = .rearR4
            case .r5: source = .rearR5
            }
            let action: TrackpadOutputAction
            switch binding {
            case let .key(key): action = .key(key, isPressed: state.isPressed(button))
            case let .mouseButton(mouse): action = .mouseButton(mouse, isPressed: state.isPressed(button))
            }
            return (source, action)
        }
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
        let task: Task<Void, Never>
        var teardown: TeardownRecord?
    }

    private struct TeardownRecord: Sendable {
        let id: UInt64
        let task: Task<TrackpadSessionStopOutcome, Never>
        var waiterCount: Int
    }

    private let runtime: Runtime
    private let eventGate = SessionEventGate()
    private var activeWorker: WorkerRecord?
    private var requestEpoch: UInt64 = 0
    private var teardownEpoch: UInt64 = 0

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
        let teardownOutcome = await teardownActiveWorker()

        guard request == requestEpoch, !Task.isCancelled else {
            return Self.finishedEventStream()
        }
        if activeWorker != nil {
            let diagnostic: String
            switch teardownOutcome {
            case .clean:
                diagnostic = "Could not start output while prior held outputs remain pending."
            case let .failed(message):
                diagnostic = message
            }
            return Self.failedEventStream(diagnostic)
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
        }
        activeWorker = WorkerRecord(
            id: request,
            stopToken: token,
            task: task,
            teardown: nil
        )
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
        if let teardown = worker.teardown {
            activeWorker?.teardown?.waiterCount += 1
            let outcome = await teardown.task.value
            return finishTeardown(
                of: worker,
                teardownID: teardown.id,
                with: outcome
            )
        }
        worker.stopToken.requestStop()
        teardownEpoch &+= 1
        let teardownID = teardownEpoch
        let teardownTask = Task.detached {
            await worker.task.value
            if let releaseAttempt = worker.stopToken.releasePendingOutputs(maxPasses: 2),
               !releaseAttempt.isDrained {
                return TrackpadSessionStopOutcome.failed(
                    "Could not release held outputs: \(releaseAttempt.diagnostic)."
                )
            }
            return TrackpadSessionStopOutcome.clean
        }
        activeWorker?.teardown = TeardownRecord(
            id: teardownID,
            task: teardownTask,
            waiterCount: 1
        )
        let outcome = await teardownTask.value
        return finishTeardown(of: worker, teardownID: teardownID, with: outcome)
    }

    private func finishTeardown(
        of worker: WorkerRecord,
        teardownID: UInt64,
        with outcome: TrackpadSessionStopOutcome
    ) -> TrackpadSessionStopOutcome {
        guard activeWorker?.id == worker.id,
              activeWorker?.teardown?.id == teardownID else { return outcome }
        switch outcome {
        case .clean:
            activeWorker = nil
        case .failed:
            activeWorker?.teardown?.waiterCount -= 1
            if activeWorker?.teardown?.waiterCount == 0 {
                activeWorker?.teardown = nil
            }
        }
        return outcome
    }

    private static func finishedEventStream() -> AsyncStream<TrackpadSessionEvent> {
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        continuation.finish()
        return stream
    }

    private static func failedEventStream(_ diagnostic: String) -> AsyncStream<TrackpadSessionEvent> {
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        continuation.yield(.failed(diagnostic))
        continuation.finish()
        return stream
    }

    #if DEBUG
    func requestEpochForTesting() -> UInt64 {
        requestEpoch
    }
    #endif

    private func advanceRequestEpoch() {
        requestEpoch &+= 1
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
