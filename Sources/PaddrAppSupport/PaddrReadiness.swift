import Foundation

public struct PaddrReadinessInput: Equatable, Sendable {
    public let isInitialized: Bool
    public let puckConnected: Bool
    public let controllerConnected: Bool
    public let batteryAvailable: Bool
    public let inputMonitoringGranted: Bool
    public let accessibilityTrusted: Bool
    public let isEnabled: Bool
    public let isRunning: Bool
    public let isReleasingOutput: Bool
    public let canToggleOutput: Bool

    public init(
        isInitialized: Bool,
        puckConnected: Bool,
        controllerConnected: Bool,
        batteryAvailable: Bool,
        inputMonitoringGranted: Bool,
        accessibilityTrusted: Bool,
        isEnabled: Bool,
        isRunning: Bool,
        isReleasingOutput: Bool,
        canToggleOutput: Bool
    ) {
        self.isInitialized = isInitialized
        self.puckConnected = puckConnected
        self.controllerConnected = controllerConnected
        self.batteryAvailable = batteryAvailable
        self.inputMonitoringGranted = inputMonitoringGranted
        self.accessibilityTrusted = accessibilityTrusted
        self.isEnabled = isEnabled
        self.isRunning = isRunning
        self.isReleasingOutput = isReleasingOutput
        self.canToggleOutput = canToggleOutput
    }
}

public enum PaddrPuckReadiness: Equatable, Sendable {
    case connected
    case notFound
}

public enum PaddrControllerReadiness: Equatable, Sendable {
    case connected
    case notFound
}

public enum PaddrBatteryReadiness: Equatable, Sendable {
    case available
    case unavailable
}

public enum PaddrOutputReadiness: Equatable, Sendable {
    case active
    case releasing
    case waiting
    case idle
}

public enum PaddrAccessReadiness: Equatable, Sendable {
    case ready
    case inputMonitoringNeeded
    case accessibilityNeeded
    case bothNeeded
}

public enum PaddrReadinessNextAction: Equatable, Sendable {
    case waitForInitialization
    case refreshPuck
    case requestInputMonitoring
    case connectController
    case requestAccessibility
    case waitForOutputRelease
    case enableOutput
    case releaseTrackpads
    case none

    public var title: LocalizedStringResource {
        switch self {
        case .waitForInitialization: "Preparing Paddr"
        case .refreshPuck: "Connect the puck, then refresh"
        case .requestInputMonitoring: "Allow Input Monitoring"
        case .connectController: "Connect the controller through the puck"
        case .requestAccessibility: "Allow Accessibility"
        case .waitForOutputRelease: "Wait for mapped input to release"
        case .enableOutput: "Enable Trackpad Output"
        case .releaseTrackpads: "Release both trackpads"
        case .none: "Ready"
        }
    }

    public var systemImage: String {
        switch self {
        case .waitForInitialization: "hourglass"
        case .refreshPuck: "cable.connector"
        case .requestInputMonitoring: "eye"
        case .connectController: "gamecontroller"
        case .requestAccessibility: "accessibility"
        case .waitForOutputRelease: "arrow.down.circle"
        case .enableOutput: "play.circle"
        case .releaseTrackpads: "hand.raised"
        case .none: "checkmark.circle.fill"
        }
    }
}

public enum PaddrOutputDisabledReason: Equatable, Sendable {
    case initializing
    case releasingOutputs
    case profileOperation

    public var message: LocalizedStringResource {
        switch self {
        case .initializing:
            "Trackpad Output is unavailable while Paddr prepares the current profile."
        case .releasingOutputs:
            "Trackpad Output is unavailable until mapped keys and mouse buttons finish releasing."
        case .profileOperation:
            "Trackpad Output is unavailable while the profile operation finishes."
        }
    }
}

public struct PaddrReadinessResolution: Equatable, Sendable {
    public let puck: PaddrPuckReadiness
    public let controller: PaddrControllerReadiness
    public let battery: PaddrBatteryReadiness
    public let output: PaddrOutputReadiness
    public let access: PaddrAccessReadiness
    public let nextAction: PaddrReadinessNextAction
    public let outputDisabledReason: PaddrOutputDisabledReason?
}

public enum PaddrReadinessResolver {
    public static func resolve(_ input: PaddrReadinessInput) -> PaddrReadinessResolution {
        let access: PaddrAccessReadiness = switch (
            input.inputMonitoringGranted,
            input.accessibilityTrusted
        ) {
        case (true, true): .ready
        case (false, true): .inputMonitoringNeeded
        case (true, false): .accessibilityNeeded
        case (false, false): .bothNeeded
        }

        let output: PaddrOutputReadiness
        if input.isRunning {
            output = .active
        } else if input.isReleasingOutput {
            output = .releasing
        } else if input.isEnabled {
            output = .waiting
        } else {
            output = .idle
        }

        let nextAction: PaddrReadinessNextAction
        if !input.isInitialized {
            nextAction = .waitForInitialization
        } else if !input.puckConnected {
            nextAction = .refreshPuck
        } else if !input.inputMonitoringGranted {
            nextAction = .requestInputMonitoring
        } else if !input.controllerConnected {
            nextAction = .connectController
        } else if !input.accessibilityTrusted {
            nextAction = .requestAccessibility
        } else if input.isReleasingOutput {
            nextAction = .waitForOutputRelease
        } else if !input.isEnabled {
            nextAction = .enableOutput
        } else if !input.isRunning {
            nextAction = .releaseTrackpads
        } else {
            nextAction = .none
        }

        let disabledReason: PaddrOutputDisabledReason?
        if input.canToggleOutput {
            disabledReason = nil
        } else if !input.isInitialized {
            disabledReason = .initializing
        } else if input.isReleasingOutput {
            disabledReason = .releasingOutputs
        } else {
            disabledReason = .profileOperation
        }

        return PaddrReadinessResolution(
            puck: input.puckConnected ? .connected : .notFound,
            controller: input.controllerConnected ? .connected : .notFound,
            battery: input.batteryAvailable ? .available : .unavailable,
            output: output,
            access: access,
            nextAction: nextAction,
            outputDisabledReason: disabledReason
        )
    }
}
