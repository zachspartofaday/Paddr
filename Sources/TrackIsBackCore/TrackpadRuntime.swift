import Foundation

public final class TrackpadStopToken: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    public init() {}

    public func requestStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    public var shouldContinue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stopped
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

public enum TrackpadSessionEvent: Sendable {
    case connecting
    case connected(String)
    case progress(TrackpadRunSummary)
    case stopped(TrackpadRunSummary)
    case failed(String)
}

public enum TrackpadRuntime {
    public static func run(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        stopToken: TrackpadStopToken,
        deadline: Date? = nil,
        onAction: (@Sendable (String) -> Void)? = nil,
        onProgress: (@Sendable (TrackpadRunSummary) -> Void)? = nil
    ) throws -> TrackpadRunSummary {
        let validated = try configuration.validated()
        let device = try TritonHIDDevice.open()
        var leftMapper = PadMapper(side: .left, configuration: validated.left)
        var rightMapper = PadMapper(side: .right, configuration: validated.right)
        let output = CGEventOutput()
        var reportCount = 0
        var actionCount = 0

        defer {
            let leftReleases = (try? leftMapper.releaseAll()) ?? []
            let rightReleases = (try? rightMapper.releaseAll()) ?? []
            if !observeOnly {
                try? output.dispatch(leftReleases + rightReleases)
            }
        }

        try device.stream(
            shouldContinue: {
                stopToken.shouldContinue && (deadline.map { Date() < $0 } ?? true)
            },
            onReport: { bytes, timestamp in
                guard let pads = TritonParser.parseTrackpads(bytes, timestampNanoseconds: timestamp) else { return }
                reportCount += 1
                let actions = try leftMapper.process(pads.left) + rightMapper.process(pads.right)
                actionCount += actions.count
                for action in actions {
                    onAction?(action.description)
                }
                if !observeOnly {
                    try output.dispatch(actions)
                }
                if reportCount.isMultiple(of: 100) {
                    onProgress?(TrackpadRunSummary(reportCount: reportCount, actionCount: actionCount))
                }
            }
        )
        return TrackpadRunSummary(reportCount: reportCount, actionCount: actionCount)
    }
}

public final class TrackpadSession: @unchecked Sendable {
    private let lock = NSLock()
    private var stopToken: TrackpadStopToken?

    public init() {}

    public func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool = false,
        onEvent: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) {
        stop()
        let token = TrackpadStopToken()
        lock.lock()
        stopToken = token
        lock.unlock()

        let thread = Thread { [weak self] in
            onEvent(.connecting)
            do {
                let deviceDescription = TritonHIDDevice.probe()?.description ?? "Steam Controller 2"
                onEvent(.connected(deviceDescription))
                let summary = try TrackpadRuntime.run(
                    configuration: configuration,
                    observeOnly: observeOnly,
                    stopToken: token,
                    onProgress: { onEvent(.progress($0)) }
                )
                onEvent(.stopped(summary))
            } catch {
                onEvent(.failed(String(describing: error)))
            }
            self?.clear(token)
        }
        thread.name = "PuckPads HID"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func stop() {
        lock.lock()
        let token = stopToken
        stopToken = nil
        lock.unlock()
        token?.requestStop()
    }

    private func clear(_ token: TrackpadStopToken) {
        lock.lock()
        if stopToken === token {
            stopToken = nil
        }
        lock.unlock()
    }
}
