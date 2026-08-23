import PaddrCore

package enum CLIExecution {
    package typealias Runtime = @Sendable (
        PaddrConfiguration,
        Bool,
        TrackpadStopToken,
        Duration?,
        @escaping @Sendable (String) -> Void
    ) throws -> TrackpadRunResult

    package static func run(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        stopToken: TrackpadStopToken,
        duration: CLIDuration?,
        onAction: @escaping @Sendable (String) -> Void,
        runtime: Runtime = liveRuntime
    ) throws -> TrackpadRunResult {
        try runtime(
            configuration,
            observeOnly,
            stopToken,
            duration?.runtimeValue,
            onAction
        )
    }

    private static func liveRuntime(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        stopToken: TrackpadStopToken,
        duration: Duration?,
        onAction: @escaping @Sendable (String) -> Void
    ) throws -> TrackpadRunResult {
        try TrackpadRuntime.run(
            configuration: configuration,
            observeOnly: observeOnly,
            stopToken: stopToken,
            duration: duration,
            onAction: onAction
        )
    }
}
