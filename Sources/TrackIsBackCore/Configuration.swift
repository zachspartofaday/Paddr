import Foundation

public enum PadSide: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

public enum PadMode: String, Codable, CaseIterable, Sendable {
    case disabled
    case mouse
    case scroll
    case dpad
}

public enum PadZoneLayout: String, Codable, CaseIterable, Sendable {
    case radialFour = "radial-four"
    case fourCorners = "four-corners"
    case horizontalTwo = "horizontal-two"
    case verticalTwo = "vertical-two"
    case gridNine = "grid-nine"

    public var displayName: String {
        switch self {
        case .radialFour: return "Four-way radial"
        case .fourCorners: return "Four corners"
        case .horizontalTwo: return "Left / right"
        case .verticalTwo: return "Top / bottom"
        case .gridNine: return "3 × 3 grid"
        }
    }
}

public enum TapBindingCatalog {
    public static let leftMouseButton = "mouse-left"
    public static let rightMouseButton = "mouse-right"

    public static func isMouseButton(_ binding: String) -> Bool {
        binding == leftMouseButton || binding == rightMouseButton
    }
}

public struct DirectionKeyConfiguration: Codable, Equatable, Sendable {
    public var up: String
    public var right: String
    public var down: String
    public var left: String

    public static let arrows = DirectionKeyConfiguration(up: "up", right: "right", down: "down", left: "left")
    public static let wasd = DirectionKeyConfiguration(up: "w", right: "d", down: "s", left: "a")

    public init(up: String, right: String, down: String, left: String) {
        self.up = up
        self.right = right
        self.down = down
        self.left = left
    }
}

public struct GridKeyConfiguration: Codable, Equatable, Sendable {
    public var topLeft: String
    public var top: String
    public var topRight: String
    public var left: String
    public var center: String
    public var right: String
    public var bottomLeft: String
    public var bottom: String
    public var bottomRight: String

    public static let keyboard = GridKeyConfiguration(
        topLeft: "q", top: "w", topRight: "e",
        left: "a", center: "space", right: "d",
        bottomLeft: "z", bottom: "x", bottomRight: "c"
    )

    public init(
        topLeft: String,
        top: String,
        topRight: String,
        left: String,
        center: String,
        right: String,
        bottomLeft: String,
        bottom: String,
        bottomRight: String
    ) {
        self.topLeft = topLeft
        self.top = top
        self.topRight = topRight
        self.left = left
        self.center = center
        self.right = right
        self.bottomLeft = bottomLeft
        self.bottom = bottom
        self.bottomRight = bottomRight
    }
}

public struct PadConfiguration: Codable, Equatable, Sendable {
    public var mode: PadMode
    public var sensitivity: Double
    public var mouseDeadzone: Double
    public var tapKey: String?
    public var tapMaximumMilliseconds: Double
    public var tapMaximumMovement: Double
    public var dpadDeadzone: Double
    public var zoneLayout: PadZoneLayout
    public var dpadKeys: DirectionKeyConfiguration
    public var gridKeys: GridKeyConfiguration

    public init(
        mode: PadMode,
        sensitivity: Double = 1,
        mouseDeadzone: Double = 0,
        tapKey: String? = nil,
        tapMaximumMilliseconds: Double = 250,
        tapMaximumMovement: Double = 2_200,
        dpadDeadzone: Double = 0.22,
        zoneLayout: PadZoneLayout = .radialFour,
        dpadKeys: DirectionKeyConfiguration = .arrows,
        gridKeys: GridKeyConfiguration = .keyboard
    ) {
        self.mode = mode
        self.sensitivity = sensitivity
        self.mouseDeadzone = mouseDeadzone
        self.tapKey = tapKey
        self.tapMaximumMilliseconds = tapMaximumMilliseconds
        self.tapMaximumMovement = tapMaximumMovement
        self.dpadDeadzone = dpadDeadzone
        self.zoneLayout = zoneLayout
        self.dpadKeys = dpadKeys
        self.gridKeys = gridKeys
    }

    private enum CodingKeys: String, CodingKey {
        case mode, sensitivity, mouseDeadzone, tapKey, tapMaximumMilliseconds, tapMaximumMovement
        case dpadDeadzone, zoneLayout, dpadKeys, gridKeys
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try values.decodeIfPresent(PadMode.self, forKey: .mode) ?? .disabled,
            sensitivity: try values.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1,
            mouseDeadzone: try values.decodeIfPresent(Double.self, forKey: .mouseDeadzone) ?? 0,
            tapKey: try values.decodeIfPresent(String.self, forKey: .tapKey),
            tapMaximumMilliseconds: try values.decodeIfPresent(Double.self, forKey: .tapMaximumMilliseconds) ?? 250,
            tapMaximumMovement: try values.decodeIfPresent(Double.self, forKey: .tapMaximumMovement) ?? 2_200,
            dpadDeadzone: try values.decodeIfPresent(Double.self, forKey: .dpadDeadzone) ?? 0.22,
            zoneLayout: try values.decodeIfPresent(PadZoneLayout.self, forKey: .zoneLayout) ?? .radialFour,
            dpadKeys: try values.decodeIfPresent(DirectionKeyConfiguration.self, forKey: .dpadKeys) ?? .arrows,
            gridKeys: try values.decodeIfPresent(GridKeyConfiguration.self, forKey: .gridKeys) ?? .keyboard
        )
    }
}

public struct TrackIsBackConfiguration: Codable, Equatable, Sendable {
    public var left: PadConfiguration
    public var right: PadConfiguration

    public static let `default` = TrackIsBackConfiguration(
        left: PadConfiguration(mode: .scroll),
        right: PadConfiguration(mode: .mouse)
    )

    private enum CodingKeys: String, CodingKey { case left, right }

    public init(left: PadConfiguration, right: PadConfiguration) {
        self.left = left
        self.right = right
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        left = try values.decodeIfPresent(PadConfiguration.self, forKey: .left) ?? Self.default.left
        right = try values.decodeIfPresent(PadConfiguration.self, forKey: .right) ?? Self.default.right
    }

    public func validated() throws -> TrackIsBackConfiguration {
        var copy = self
        try copy.validate(side: .left, pad: &copy.left)
        try copy.validate(side: .right, pad: &copy.right)
        return copy
    }

    private func validate(side: PadSide, pad: inout PadConfiguration) throws {
        guard pad.sensitivity.isFinite, pad.sensitivity > 0 else {
            throw TrackIsBackError.configuration("\(side.rawValue) sensitivity must be a positive finite number.")
        }
        guard pad.mouseDeadzone.isFinite, (0...1).contains(pad.mouseDeadzone) else {
            throw TrackIsBackError.configuration("\(side.rawValue) mouseDeadzone must be between 0 and 1.")
        }
        guard pad.tapMaximumMilliseconds.isFinite, pad.tapMaximumMilliseconds > 0 else {
            throw TrackIsBackError.configuration("\(side.rawValue) tapMaximumMilliseconds must be positive.")
        }
        guard pad.tapMaximumMovement.isFinite, pad.tapMaximumMovement >= 0 else {
            throw TrackIsBackError.configuration("\(side.rawValue) tapMaximumMovement must be zero or greater.")
        }
        guard pad.dpadDeadzone.isFinite, (0..<1).contains(pad.dpadDeadzone) else {
            throw TrackIsBackError.configuration("\(side.rawValue) dpadDeadzone must be at least 0 and less than 1.")
        }
        if let tapKey = pad.tapKey {
            pad.tapKey = try normalizedOutputBinding(tapKey)
        }
        if pad.mode == .dpad {
            pad.dpadKeys.up = try normalizedOutputBinding(pad.dpadKeys.up)
            pad.dpadKeys.right = try normalizedOutputBinding(pad.dpadKeys.right)
            pad.dpadKeys.down = try normalizedOutputBinding(pad.dpadKeys.down)
            pad.dpadKeys.left = try normalizedOutputBinding(pad.dpadKeys.left)
            if pad.zoneLayout == .gridNine {
                pad.gridKeys.topLeft = try normalizedOutputBinding(pad.gridKeys.topLeft)
                pad.gridKeys.top = try normalizedOutputBinding(pad.gridKeys.top)
                pad.gridKeys.topRight = try normalizedOutputBinding(pad.gridKeys.topRight)
                pad.gridKeys.left = try normalizedOutputBinding(pad.gridKeys.left)
                pad.gridKeys.center = try normalizedOutputBinding(pad.gridKeys.center)
                pad.gridKeys.right = try normalizedOutputBinding(pad.gridKeys.right)
                pad.gridKeys.bottomLeft = try normalizedOutputBinding(pad.gridKeys.bottomLeft)
                pad.gridKeys.bottom = try normalizedOutputBinding(pad.gridKeys.bottom)
                pad.gridKeys.bottomRight = try normalizedOutputBinding(pad.gridKeys.bottomRight)
            }
        }
    }

    private func normalizedOutputBinding(_ binding: String) throws -> String {
        TapBindingCatalog.isMouseButton(binding) ? binding : try KeyCatalog.resolve(binding).name
    }
}

public enum TrackIsBackError: Error, CustomStringConvertible, Sendable {
    case configuration(String)
    case device(String)
    case permission(String)
    case output(String)

    public var description: String {
        switch self {
        case let .configuration(message), let .device(message), let .permission(message), let .output(message):
            return message
        }
    }
}
