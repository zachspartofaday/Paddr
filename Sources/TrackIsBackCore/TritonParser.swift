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

public enum TritonParser {
    private static let rightTouchMask: UInt32 = 0x0020_0000
    private static let rightClickMask: UInt32 = 0x0040_0000
    private static let leftTouchMask: UInt32 = 0x0200_0000
    private static let leftClickMask: UInt32 = 0x0400_0000

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
