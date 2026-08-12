import Foundation

public enum MenuFailure: Equatable, Sendable {
    case inputMonitoringRequired
    case accessibilityRequired
    case configurationLoad(diagnostic: String)
    case configurationInvalid(diagnostic: String)
    case configurationSave(diagnostic: String)
    case output(diagnostic: String)
    case unexpected(diagnostic: String)

    public var message: LocalizedStringResource {
        switch self {
        case .inputMonitoringRequired:
            LocalizedStringResource("Input Monitoring is required before Paddr can read the trackpads.")
        case .accessibilityRequired:
            LocalizedStringResource("Accessibility is required before Paddr can emit mapped input.")
        case .configurationLoad:
            LocalizedStringResource("Saved settings could not be loaded. Defaults are shown.")
        case .configurationInvalid:
            LocalizedStringResource("Some settings are invalid. Review the values and try again.")
        case .configurationSave:
            LocalizedStringResource("Settings could not be saved. Your edits are still available.")
        case .output:
            LocalizedStringResource("Trackpad output stopped because of an error.")
        case .unexpected:
            LocalizedStringResource("An unexpected error occurred.")
        }
    }

    public var diagnostic: String? {
        switch self {
        case .inputMonitoringRequired, .accessibilityRequired:
            nil
        case let .configurationLoad(diagnostic),
             let .configurationInvalid(diagnostic),
             let .configurationSave(diagnostic),
             let .output(diagnostic),
             let .unexpected(diagnostic):
            diagnostic
        }
    }
}

public enum MenuStatusMessageState: Equatable, Sendable {
    case guidance
    case failure
}

public enum MenuStatus: Equatable, Sendable {
    case off
    case waitingForController
    case connecting
    case active
    case configurationSaved
    case defaultsRestored
    case requestingInputMonitoring
    case requestingAccessibility
    case inputMonitoringSettings
    case accessibilitySettings
    case releasingOutputs
    case stopped
    case failure(MenuFailure)

    public var message: LocalizedStringResource {
        switch self {
        case .off: "Trackpad output is off."
        case .waitingForController: "Waiting for Steam Controller 2 through the puck…"
        case .connecting: "Connecting…"
        case .active: "Trackpad output is active."
        case .configurationSaved: "Configuration saved."
        case .defaultsRestored: "Defaults restored. Save to apply them."
        case .requestingInputMonitoring: "Complete the Input Monitoring prompt, then return to Paddr."
        case .requestingAccessibility: "Complete the Accessibility prompt, then return to Paddr."
        case .inputMonitoringSettings: "Enable Paddr in Input Monitoring, then return to the app."
        case .accessibilitySettings: "Enable Paddr in Accessibility, then return to the app."
        case .releasingOutputs: "Releasing mapped keys and mouse buttons…"
        case .stopped: "Trackpad output stopped."
        case let .failure(failure): failure.message
        }
    }

    public var messageState: MenuStatusMessageState? {
        switch self {
        case .defaultsRestored, .requestingInputMonitoring, .requestingAccessibility,
             .inputMonitoringSettings, .accessibilitySettings:
            .guidance
        case .failure:
            .failure
        case .off, .waitingForController, .connecting, .active, .configurationSaved,
             .releasingOutputs, .stopped:
            nil
        }
    }

    public var needsActionMessage: Bool { messageState != nil }
}

public enum InputMonitoringStatus: String, Equatable, Sendable {
    case granted
    case denied
    case unknown
    case unsupported
}
