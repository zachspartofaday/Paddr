import Foundation

public enum MenuFailure: Equatable, Sendable {
    case accessibilityRequired
    case configurationRecovered(diagnostic: String)
    case configurationLoad(diagnostic: String)
    case configurationInvalid(diagnostic: String)
    case configurationSave(diagnostic: String)
    case profileInvalid(diagnostic: String)
    case profileSave(diagnostic: String)
    case output(diagnostic: String)
    case terminationRelease(diagnostic: String)
    case unexpected(diagnostic: String)

    public var message: LocalizedStringResource {
        switch self {
        case .accessibilityRequired:
            LocalizedStringResource("Enable Paddr in Accessibility, then turn Trackpad Output on again.")
        case .configurationRecovered:
            LocalizedStringResource("Paddr repaired the saved profile selection. Review the profiles, then choose Save & Apply.")
        case .configurationLoad:
            LocalizedStringResource("Saved settings couldn’t be loaded. Repair or move the existing configuration file in ~/.config/Paddr, ~/.config/PuckPads, ~/.config/TracksBack, or ~/.config/TrackIsBack, then reopen Paddr.")
        case .configurationInvalid:
            LocalizedStringResource("Some settings are invalid. Review the values, then choose Save & Apply again.")
        case .configurationSave:
            LocalizedStringResource("Settings couldn’t be saved. Your edits are still available. Try saving again.")
        case .profileInvalid:
            LocalizedStringResource("Profile change couldn’t be completed. Review the profile details, then try again.")
        case .profileSave:
            LocalizedStringResource("Profile change couldn’t be saved. Make the change again. If it still fails, reopen Paddr.")
        case .output:
            LocalizedStringResource("Trackpad output stopped because of an error. Check the puck and controller, then turn Trackpad Output on again.")
        case .terminationRelease:
            LocalizedStringResource("Paddr couldn’t finish releasing mapped input. Quit Paddr again to retry cleanup.")
        case .unexpected:
            LocalizedStringResource("An unexpected error occurred. Reopen Paddr, then try again.")
        }
    }

    public var diagnostic: String? {
        switch self {
        case .accessibilityRequired:
            nil
        case let .configurationRecovered(diagnostic),
             let .configurationLoad(diagnostic),
             let .configurationInvalid(diagnostic),
             let .configurationSave(diagnostic),
             let .profileInvalid(diagnostic),
             let .profileSave(diagnostic),
             let .output(diagnostic),
             let .terminationRelease(diagnostic),
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
    case waitingForNeutral
    case connecting
    case active
    case configurationSaved
    case defaultsRestored
    case requestingAccessibility
    case accessibilitySettings
    case requestingInputMonitoring
    case inputMonitoringSettings
    case releasingOutputs
    case stopped
    case failure(MenuFailure)

    public var message: LocalizedStringResource {
        switch self {
        case .off: "Trackpad output is off."
        case .waitingForController: "Waiting for Steam Controller 2 through the puck…"
        case .waitingForNeutral: "Release both trackpads to activate output…"
        case .connecting: "Connecting…"
        case .active: "Trackpad output is active."
        case .configurationSaved: "Configuration saved."
        case .defaultsRestored: "Defaults restored. Save to apply them."
        case .requestingAccessibility: "Complete the Accessibility prompt, then return to Paddr."
        case .accessibilitySettings: "Enable Paddr in Accessibility, then return to the app."
        case .requestingInputMonitoring: "Complete the Input Monitoring prompt, then return to Paddr."
        case .inputMonitoringSettings: "Enable Paddr in Input Monitoring (add it with + if it isn't listed), then relaunch Paddr."
        case .releasingOutputs: "Releasing mapped keys and mouse buttons…"
        case .stopped: "Trackpad output stopped."
        case let .failure(failure): failure.message
        }
    }

    public var messageState: MenuStatusMessageState? {
        switch self {
        case .waitingForNeutral, .defaultsRestored, .requestingAccessibility, .accessibilitySettings,
             .requestingInputMonitoring, .inputMonitoringSettings:
            .guidance
        case .failure:
            .failure
        case .off, .waitingForController, .connecting, .active,
             .configurationSaved, .releasingOutputs, .stopped:
            nil
        }
    }

    public var needsActionMessage: Bool { messageState != nil }
}
