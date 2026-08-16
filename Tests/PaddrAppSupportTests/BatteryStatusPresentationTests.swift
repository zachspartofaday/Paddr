import XCTest
@testable import PaddrAppSupport
import PaddrCore

final class BatteryStatusPresentationTests: XCTestCase {
    func testUnavailablePresentationUsesReservedPlaceholderAndNativeMenuCopy() {
        let presentation = BatteryStatusPresentation(status: nil)

        XCTAssertEqual(presentation.compactValue, "—")
        XCTAssertEqual(presentation.systemImage, "battery.0percent")
        XCTAssertEqual(presentation.accessibilityValue, "Status unavailable")
        XCTAssertEqual(presentation.menuLevel, "Battery level: —")
        XCTAssertEqual(presentation.menuChargeState, "Charge state: —")
    }

    func testChargingPresentationIncludesCompactPercentAndAccessibleChargeState() {
        let presentation = BatteryStatusPresentation(
            status: .init(chargeState: .charging, percentage: 82)
        )

        XCTAssertEqual(presentation.compactValue, "82%")
        XCTAssertEqual(presentation.systemImage, "battery.100percent.bolt")
        XCTAssertEqual(presentation.accessibilityValue, "Level 82%, Charging")
        XCTAssertEqual(presentation.menuLevel, "Battery level: 82%")
        XCTAssertEqual(presentation.menuChargeState, "Charge state: Charging")
    }

    func testLevelGlyphsAndKnownAndUnknownMenuStates() {
        let levelGlyphs: [(UInt8, String)] = [
            (0, "battery.0percent"),
            (25, "battery.25percent"),
            (50, "battery.50percent"),
            (75, "battery.75percent"),
            (100, "battery.100percent")
        ]
        for (percentage, expectedGlyph) in levelGlyphs {
            let presentation = BatteryStatusPresentation(
                status: .init(chargeState: .discharging, percentage: percentage)
            )
            XCTAssertEqual(presentation.systemImage, expectedGlyph)
        }

        let chargeStates: [(ControllerBatteryChargeState, String)] = [
            (.reset, "Charge state: Reset"),
            (.discharging, "Charge state: Discharging"),
            (.charging, "Charge state: Charging"),
            (.sourceValidate, "Charge state: Validating source"),
            (.chargingDone, "Charge state: Charging complete"),
            (.unknown(0xFE), "Charge state: Unknown")
        ]
        for (chargeState, expectedMenuCopy) in chargeStates {
            let presentation = BatteryStatusPresentation(
                status: .init(chargeState: chargeState, percentage: 50)
            )
            XCTAssertEqual(presentation.menuChargeState, expectedMenuCopy)
        }
    }
}
