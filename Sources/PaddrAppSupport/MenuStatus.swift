import Foundation

public enum MenuFailure: Equatable, Sendable {
    case accessibilityRequired
    case configurationLoad(diagnostic: String)
    case configurationInvalid(diagnostic: String)
    case configurationSave(diagnostic: String)
    case output(diagnostic: String)
    case unexpected(diagnostic: String)

    public var message: LocalizedStringResource {
        switch self {
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
        case .accessibilityRequired:
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
    case waitingForNeutral
    case connecting
    case active
    case configurationSaved
    case defaultsRestored
    case requestingAccessibility
    case accessibilitySettings
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
        case .releasingOutputs: "Releasing mapped keys and mouse buttons…"
        case .stopped: "Trackpad output stopped."
        case let .failure(failure): failure.message
        }
    }

    public var messageState: MenuStatusMessageState? {
        switch self {
        case .defaultsRestored, .requestingAccessibility, .accessibilitySettings:
            .guidance
        case .failure:
            .failure
        case .off, .waitingForController, .waitingForNeutral, .connecting, .active,
             .configurationSaved, .releasingOutputs, .stopped:
            nil
        }
    }

    public var needsActionMessage: Bool { messageState != nil }
}
