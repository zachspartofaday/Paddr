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

    public var allowsTouchTap: Bool {
        self == .mouse || self == .scroll
    }
}

public enum CenterTapTrackingMode: String, Codable, CaseIterable, Sendable {
    case coupled
    case decoupled
}

public enum ConfigurationLimits {
    public static let sensitivity = 0.1...20.0
    public static let scrollSensitivity = 0.0...1.0
    public static let mouseAcceleration = 0.0...1.0
    public static let tapMaximumMilliseconds = 1.0...5_000.0
    public static let tapMaximumMovement = 0.0...100_000.0
    public static let mouseDeadzone = 0.0...1.0

    public static func containsDPadDeadzone(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value < 1
    }
}

public enum PadZoneLayout: String, Codable, CaseIterable, Sendable {
    case radialFour = "radial-four"
    case fourCorners = "four-corners"
    case horizontalTwo = "horizontal-two"
    case verticalTwo = "vertical-two"
    case gridNine = "grid-nine"

    public var displayName: LocalizedStringResource {
        switch self {
        case .radialFour: LocalizedStringResource("Four-way radial")
        case .fourCorners: LocalizedStringResource("Four corners")
        case .horizontalTwo: LocalizedStringResource("Left / right")
        case .verticalTwo: LocalizedStringResource("Top / bottom")
        case .gridNine: LocalizedStringResource("3 × 3 grid")
        }
    }

    public var zones: [ButtonZone] {
        switch self {
        case .radialFour: [.up, .right, .down, .left]
        case .fourCorners: [.topLeft, .topRight, .bottomRight, .bottomLeft]
        case .horizontalTwo: [.left, .right]
        case .verticalTwo: [.up, .down]
        case .gridNine:
            [.topLeft, .up, .topRight, .left, .center, .right, .bottomLeft, .down, .bottomRight]
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
    public var scrollSensitivity: Double
    public var mouseAcceleration: Double
    public var mouseDeadzone: Double
    public var centerTapTrackingMode: CenterTapTrackingMode
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
        scrollSensitivity: Double = 1,
        mouseAcceleration: Double = 0,
        mouseDeadzone: Double = 0,
        centerTapTrackingMode: CenterTapTrackingMode = .decoupled,
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
        self.scrollSensitivity = scrollSensitivity
        self.mouseAcceleration = mouseAcceleration
        self.mouseDeadzone = mouseDeadzone
        self.centerTapTrackingMode = centerTapTrackingMode
        self.tapKey = tapKey
        self.tapMaximumMilliseconds = tapMaximumMilliseconds
        self.tapMaximumMovement = tapMaximumMovement
        self.dpadDeadzone = dpadDeadzone
        self.zoneLayout = zoneLayout
        self.dpadKeys = dpadKeys
        self.gridKeys = gridKeys
    }

    public subscript(bindingFor zone: ButtonZone) -> String {
        get {
            if zoneLayout == .gridNine {
                switch zone {
                case .topLeft: return gridKeys.topLeft
                case .up: return gridKeys.top
                case .topRight: return gridKeys.topRight
                case .left: return gridKeys.left
                case .center: return gridKeys.center
                case .right: return gridKeys.right
                case .bottomLeft: return gridKeys.bottomLeft
                case .down: return gridKeys.bottom
                case .bottomRight: return gridKeys.bottomRight
                }
            }
            switch zone {
            case .topLeft, .up: return dpadKeys.up
            case .topRight, .right: return dpadKeys.right
            case .bottomRight, .down: return dpadKeys.down
            case .bottomLeft, .left: return dpadKeys.left
            case .center: return gridKeys.center
            }
        }
        set {
            if zoneLayout == .gridNine {
                switch zone {
                case .topLeft: gridKeys.topLeft = newValue
                case .up: gridKeys.top = newValue
                case .topRight: gridKeys.topRight = newValue
                case .left: gridKeys.left = newValue
                case .center: gridKeys.center = newValue
                case .right: gridKeys.right = newValue
                case .bottomLeft: gridKeys.bottomLeft = newValue
                case .down: gridKeys.bottom = newValue
                case .bottomRight: gridKeys.bottomRight = newValue
                }
                return
            }
            switch zone {
            case .topLeft, .up: dpadKeys.up = newValue
            case .topRight, .right: dpadKeys.right = newValue
            case .bottomRight, .down: dpadKeys.down = newValue
            case .bottomLeft, .left: dpadKeys.left = newValue
            case .center: gridKeys.center = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mode, sensitivity, scrollSensitivity, mouseAcceleration, mouseDeadzone, centerTapTrackingMode
        case tapKey, tapMaximumMilliseconds, tapMaximumMovement, dpadDeadzone, zoneLayout, dpadKeys, gridKeys
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sensitivity = try values.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1
        self.init(
            mode: try values.decodeIfPresent(PadMode.self, forKey: .mode) ?? .disabled,
            sensitivity: sensitivity,
            scrollSensitivity: try values.decodeIfPresent(Double.self, forKey: .scrollSensitivity)
                ?? min(sensitivity, ConfigurationLimits.scrollSensitivity.upperBound),
            mouseAcceleration: try values.decodeIfPresent(Double.self, forKey: .mouseAcceleration) ?? 0,
            mouseDeadzone: try values.decodeIfPresent(Double.self, forKey: .mouseDeadzone) ?? 0,
            centerTapTrackingMode: try values.decodeIfPresent(
                CenterTapTrackingMode.self,
                forKey: .centerTapTrackingMode
            ) ?? .coupled,
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
        var missingLeft = Self.default.left
        var missingRight = Self.default.right
        missingLeft.centerTapTrackingMode = .coupled
        missingRight.centerTapTrackingMode = .coupled
        left = try values.decodeIfPresent(PadConfiguration.self, forKey: .left) ?? missingLeft
        right = try values.decodeIfPresent(PadConfiguration.self, forKey: .right) ?? missingRight
    }

    public func validated() throws -> TrackIsBackConfiguration {
        var copy = self
        try copy.validate(side: .left, pad: &copy.left)
        try copy.validate(side: .right, pad: &copy.right)
        return copy
    }

    private func validate(side: PadSide, pad: inout PadConfiguration) throws {
        guard pad.sensitivity.isFinite, ConfigurationLimits.sensitivity.contains(pad.sensitivity) else {
            throw TrackIsBackError.configuration("\(side.rawValue) sensitivity must be between 0.1 and 20.")
        }
        guard pad.scrollSensitivity.isFinite,
              ConfigurationLimits.scrollSensitivity.contains(pad.scrollSensitivity) else {
            throw TrackIsBackError.configuration("\(side.rawValue) scrollSensitivity must be between 0 and 1.")
        }
        guard pad.mouseAcceleration.isFinite,
              ConfigurationLimits.mouseAcceleration.contains(pad.mouseAcceleration) else {
            throw TrackIsBackError.configuration("\(side.rawValue) mouseAcceleration must be between 0 and 1.")
        }
        guard pad.mouseDeadzone.isFinite, ConfigurationLimits.mouseDeadzone.contains(pad.mouseDeadzone) else {
            throw TrackIsBackError.configuration("\(side.rawValue) mouseDeadzone must be between 0 and 1.")
        }
        guard pad.tapMaximumMilliseconds.isFinite,
              ConfigurationLimits.tapMaximumMilliseconds.contains(pad.tapMaximumMilliseconds) else {
            throw TrackIsBackError.configuration("\(side.rawValue) tapMaximumMilliseconds must be between 1 and 5000.")
        }
        guard pad.tapMaximumMovement.isFinite,
              ConfigurationLimits.tapMaximumMovement.contains(pad.tapMaximumMovement) else {
            throw TrackIsBackError.configuration("\(side.rawValue) tapMaximumMovement must be between 0 and 100000.")
        }
        guard ConfigurationLimits.containsDPadDeadzone(pad.dpadDeadzone) else {
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
