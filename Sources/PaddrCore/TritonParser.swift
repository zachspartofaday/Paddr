import Foundation

public struct TrackpadSample: Equatable, Sendable {
    public var isTouched: Bool
    public var isClicked: Bool
    public var x: Int16
    public var y: Int16
    public var pressure: UInt16
    public var timestampNanoseconds: UInt64

    public init(isTouched: Bool, isClicked: Bool, x: Int16, y: Int16, pressure: UInt16, timestampNanoseconds: UInt64) {
        self.isTouched = isTouched
        self.isClicked = isClicked
        self.x = x
        self.y = y
        self.pressure = pressure
        self.timestampNanoseconds = timestampNanoseconds
    }
}

public struct TrackpadPair: Equatable, Sendable {
    public var left: TrackpadSample
    public var right: TrackpadSample
}

public enum ControllerBatteryChargeState: Equatable, Sendable {
    case reset
    case discharging
    case charging
    case sourceValidate
    case chargingDone
    case unknown(UInt8)

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .reset
        case 1: self = .discharging
        case 2: self = .charging
        case 3: self = .sourceValidate
        case 4: self = .chargingDone
        default: self = .unknown(rawValue)
        }
    }
}

public struct ControllerBatteryStatus: Equatable, Sendable {
    public let chargeState: ControllerBatteryChargeState
    public let percentage: UInt8

    public init(chargeState: ControllerBatteryChargeState, percentage: UInt8) {
        self.chargeState = chargeState
        self.percentage = percentage
    }
}

public enum TritonParser {
    private static let rightTouchMask: UInt32 = 0x0020_0000
    private static let rightClickMask: UInt32 = 0x0040_0000
    private static let leftTouchMask: UInt32 = 0x0200_0000
    private static let leftClickMask: UInt32 = 0x0400_0000

    // Wireless-status report IDs and state values follow SDL's ETritonReportIDTypes /
    // ETritonWirelessState (0x46 = ID_TRITON_WIRELESS_STATUS_X, 0x79 = ID_TRITON_WIRELESS_STATUS).
    private static let wirelessStatusReportIDs: Set<UInt8> = [0x46, 0x79]
    private static let wirelessStateDisconnected: UInt8 = 1
    private static let wirelessStateConnected: UInt8 = 2
    private static let batteryStatusReportID: UInt8 = 0x43
    private static let minimumBatteryStatusReportLength = 15

    /// Returns the link state carried by a dongle wireless-status report, or nil when the
    /// bytes are not a wireless-status report with a recognized state.
    public static func parseWirelessConnection(_ bytes: [UInt8]) -> Bool? {
        guard bytes.count >= 2, let report = bytes.first, wirelessStatusReportIDs.contains(report) else { return nil }
        switch bytes[1] {
        case wirelessStateConnected: return true
        case wirelessStateDisconnected: return false
        default: return nil
        }
    }

    /// Parses the packed dongle battery-status report. The report is an ID byte followed by
    /// a 14-byte payload; only charge state and percentage are surfaced by Paddr.
    public static func parseBatteryStatus(_ bytes: [UInt8]) -> ControllerBatteryStatus? {
        guard bytes.count >= minimumBatteryStatusReportLength,
              bytes[0] == batteryStatusReportID,
              bytes[2] <= 100
        else { return nil }
        return ControllerBatteryStatus(
            chargeState: ControllerBatteryChargeState(rawValue: bytes[1]),
            percentage: bytes[2]
        )
    }

    public static func parseTrackpads(_ bytes: [UInt8], timestampNanoseconds: UInt64) -> TrackpadPair? {
        guard let report = bytes.first else { return nil }
        let padOffset: Int
        switch report {
        case 0x42, 0x45:
            padOffset = 18
        case 0x47:
            padOffset = 20
        default:
            return nil
        }
        guard bytes.count >= padOffset + 12,
              let buttons = uint32LE(bytes, at: 2),
              let leftX = int16LE(bytes, at: padOffset),
              let leftY = int16LE(bytes, at: padOffset + 2),
              let leftPressure = uint16LE(bytes, at: padOffset + 4),
              let rightX = int16LE(bytes, at: padOffset + 6),
              let rightY = int16LE(bytes, at: padOffset + 8),
              let rightPressure = uint16LE(bytes, at: padOffset + 10)
        else { return nil }

        return TrackpadPair(
            left: TrackpadSample(
                isTouched: buttons & leftTouchMask != 0,
                isClicked: buttons & leftClickMask != 0,
                x: leftX,
                y: leftY,
                pressure: leftPressure,
                timestampNanoseconds: timestampNanoseconds
            ),
            right: TrackpadSample(
                isTouched: buttons & rightTouchMask != 0,
                isClicked: buttons & rightClickMask != 0,
                x: rightX,
                y: rightY,
                pressure: rightPressure,
                timestampNanoseconds: timestampNanoseconds
            )
        )
    }

    private static func uint16LE(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= bytes.count - 2 else { return nil }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func int16LE(_ bytes: [UInt8], at offset: Int) -> Int16? {
        uint16LE(bytes, at: offset).map { Int16(bitPattern: $0) }
    }

    private static func uint32LE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= bytes.count - 4 else { return nil }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
