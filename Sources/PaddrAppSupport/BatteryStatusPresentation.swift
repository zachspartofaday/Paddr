import Foundation
import TrackIsBackCore

public struct BatteryStatusPresentation: Equatable, Sendable {
    public let compactValue: String
    public let systemImage: String
    public let accessibilityValue: String
    public let menuLevel: String
    public let menuChargeState: String

    public init(status: ControllerBatteryStatus?) {
        guard let status else {
            compactValue = "—"
            systemImage = "battery.0percent"
            accessibilityValue = String(localized: "Status unavailable")
            menuLevel = String(localized: "Battery level: —")
            menuChargeState = String(localized: "Charge state: —")
            return
        }

        let percentage = Int(status.percentage)
        let percentageText = percentage.formatted(
            .percent.scale(1).precision(.fractionLength(0))
        )
        let chargeStateText = Self.chargeStateText(status.chargeState)
        compactValue = percentageText
        systemImage = status.chargeState == .charging
            ? "battery.100percent.bolt"
            : Self.levelSystemImage(percentage: percentage)
        accessibilityValue = String(localized: "Level \(percentageText), \(chargeStateText)")
        menuLevel = String(localized: "Battery level: \(percentageText)")
        menuChargeState = String(localized: "Charge state: \(chargeStateText)")
    }

    private static func chargeStateText(_ state: ControllerBatteryChargeState) -> String {
        switch state {
        case .reset: String(localized: "Reset")
        case .discharging: String(localized: "Discharging")
        case .charging: String(localized: "Charging")
        case .sourceValidate: String(localized: "Validating source")
        case .chargingDone: String(localized: "Charging complete")
        case .unknown: String(localized: "Unknown")
        }
    }

    private static func levelSystemImage(percentage: Int) -> String {
        switch percentage {
        case 0...12: "battery.0percent"
        case 13...37: "battery.25percent"
        case 38...62: "battery.50percent"
        case 63...87: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
