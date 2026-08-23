import Foundation

public enum MenuBarTintRole: Equatable, Sendable {
    case active
    case warning
    case none
}

public struct MenuBarPresentation: Equatable, Sendable {
    public let outputSummary: String
    public let controllerSummary: String
    public let transportSummary: String
    public let profileSummary: String
    public let accessibilityLabel: String
    public let symbolName: String
    public let usesTemplateImage: Bool
    public let tintRole: MenuBarTintRole

    public init(
        isEnabled: Bool,
        isRunning: Bool,
        isReleasingOutput: Bool,
        controllerConnected: Bool,
        puckConnected: Bool,
        profileName: String
    ) {
        let outputValue: String
        if isRunning {
            outputValue = String(localized: "Active")
        } else if isReleasingOutput {
            outputValue = String(localized: "Releasing")
        } else if isEnabled {
            outputValue = String(localized: "Waiting")
        } else {
            outputValue = String(localized: "Idle")
        }

        let controllerValue = controllerConnected
            ? String(localized: "Connected")
            : String(localized: "Not found")
        let transportValue = puckConnected
            ? String(localized: "Puck connected")
            : String(localized: "Puck not found")

        outputSummary = String(
            localized: "Output: \(outputValue)",
            comment: "Status-menu summary for mapped output"
        )
        controllerSummary = String(
            localized: "Controller: \(controllerValue)",
            comment: "Status-menu summary for controller connection"
        )
        transportSummary = String(
            localized: "Transport: \(transportValue)",
            comment: "Status-menu summary for the puck transport"
        )
        profileSummary = String(
            localized: "Profile: \(profileName)",
            comment: "Status-menu summary for the active profile; the argument is its user-visible name"
        )
        accessibilityLabel = String(
            localized: "Paddr. \(outputSummary). \(controllerSummary). \(transportSummary). \(profileSummary).",
            comment: "Menu-bar status item summary in output, controller, transport, profile order"
        )
        if isReleasingOutput {
            symbolName = "arrow.down.circle.fill"
        } else if isRunning {
            symbolName = "hand.point.up.left.fill"
        } else if isEnabled {
            symbolName = "hourglass.circle.fill"
        } else {
            symbolName = "hand.point.up.left"
        }
        usesTemplateImage = !isEnabled
        tintRole = if !isEnabled {
            .none
        } else if controllerConnected && isRunning {
            .active
        } else {
            .warning
        }
    }
}
