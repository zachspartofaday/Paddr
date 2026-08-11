import Foundation

public enum DPadDirection: String, CaseIterable, Hashable, Sendable {
    case up
    case right
    case down
    case left
}

public enum MouseButtonBinding: String, Equatable, Hashable, Sendable {
    case left
    case right
}

public enum ButtonZone: String, CaseIterable, Hashable, Sendable {
    case topLeft
    case up
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case down
    case bottomRight
}

public enum TrackpadOutputAction: Equatable, Sendable {
    case mouseMove(dx: Double, dy: Double)
    case mouseButton(MouseButtonBinding, isPressed: Bool)
    case scroll(dx: Double, dy: Double)
    case key(KeyBinding, isPressed: Bool)

    public var description: String {
        switch self {
        case let .mouseMove(dx, dy): return String(format: "mouse dx=%.2f dy=%.2f", dx, dy)
        case let .mouseButton(button, isPressed): return "mouse \(button.rawValue) \(isPressed ? "down" : "up")"
        case let .scroll(dx, dy): return String(format: "scroll dx=%.2f dy=%.2f", dx, dy)
        case let .key(key, isPressed): return "key \(key.name) \(isPressed ? "down" : "up")"
        }
    }
}

public struct PadMapper: Sendable {
    let side: PadSide
    let configuration: PadConfiguration

    private var previous: TrackpadSample?
    private var activeZones: Set<ButtonZone> = []
    private var tapOrigin: (x: Int16, y: Int16, timestamp: UInt64)?
    private var tapEligible = false

    public init(side: PadSide, configuration: PadConfiguration) {
        self.side = side
        self.configuration = configuration
    }

    public mutating func process(_ sample: TrackpadSample) throws -> [TrackpadOutputAction] {
        let wasTouched = previous?.isTouched == true
        var actions: [TrackpadOutputAction] = []

        if configuration.mode.allowsTouchTap, sample.isTouched, !wasTouched {
            tapOrigin = (sample.x, sample.y, sample.timestampNanoseconds)
            tapEligible = configuration.mode == .scroll
                || configuration.mouseDeadzone == 0
                || Self.isInsideMouseDeadzone(sample, deadzone: configuration.mouseDeadzone)
        }
        updateTapEligibility(with: sample)

        switch configuration.mode {
        case .disabled:
            actions += try updateButtonZones(to: [])
        case .mouse:
            if sample.isTouched,
               let previous,
               previous.isTouched,
               !Self.isInsideMouseDeadzone(sample, deadzone: configuration.mouseDeadzone),
               !Self.isInsideMouseDeadzone(previous, deadzone: configuration.mouseDeadzone) {
                let dx = Double(Int(sample.x) - Int(previous.x)) / 700.0 * configuration.sensitivity
                let dy = -Double(Int(sample.y) - Int(previous.y)) / 700.0 * configuration.sensitivity
                if abs(dx) >= 0.05 || abs(dy) >= 0.05 {
                    actions.append(.mouseMove(dx: dx, dy: dy))
                }
            }
        case .scroll:
            if sample.isTouched, let previous, previous.isTouched {
                let dx = Double(Int(sample.x) - Int(previous.x)) / 240.0 * configuration.sensitivity
                let dy = -Double(Int(sample.y) - Int(previous.y)) / 240.0 * configuration.sensitivity
                if abs(dx) >= 0.25 || abs(dy) >= 0.25 {
                    actions.append(.scroll(dx: dx, dy: dy))
                }
            }
        case .dpad:
            let zones = sample.isTouched
                ? Self.activeButtonZones(
                    x: sample.x,
                    y: sample.y,
                    deadzone: configuration.dpadDeadzone,
                    layout: configuration.zoneLayout
                )
                : []
            if !zones.isEmpty { tapEligible = false }
            actions += try updateButtonZones(to: zones)
        }

        if !sample.isTouched, wasTouched {
            actions += try updateButtonZones(to: [])
            if configuration.mode.allowsTouchTap,
               tapEligible,
               let origin = tapOrigin,
               let tapKey = configuration.tapKey {
                let elapsed = sample.timestampNanoseconds >= origin.timestamp
                    ? sample.timestampNanoseconds - origin.timestamp
                    : UInt64.max
                let milliseconds = min(
                    max(configuration.tapMaximumMilliseconds, ConfigurationLimits.tapMaximumMilliseconds.lowerBound),
                    ConfigurationLimits.tapMaximumMilliseconds.upperBound
                )
                let maximum = UInt64(milliseconds * 1_000_000)
                if elapsed <= maximum {
                    actions += try tapActions(for: tapKey)
                }
            }
            tapOrigin = nil
            tapEligible = false
        }

        previous = sample
        return actions
    }

    public mutating func releaseAll() throws -> [TrackpadOutputAction] {
        defer {
            activeZones.removeAll()
            previous = nil
            tapOrigin = nil
            tapEligible = false
        }
        return try activeZones
            .sorted { Self.sortOrder($0) < Self.sortOrder($1) }
            .map { try outputAction(for: $0, isPressed: false) }
    }

    public static func activeDirections(
        x: Int16,
        y: Int16,
        deadzone: Double,
        layout: PadZoneLayout = .radialFour
    ) -> Set<DPadDirection> {
        Set(activeButtonZones(x: x, y: y, deadzone: deadzone, layout: layout).compactMap { zone in
            switch zone {
            case .up: return .up
            case .right: return .right
            case .down: return .down
            case .left: return .left
            case .topLeft: return .up
            case .topRight: return .right
            case .bottomRight: return .down
            case .bottomLeft: return .left
            case .center: return nil
            }
        })
    }

    public static func activeButtonZones(
        x: Int16,
        y: Int16,
        deadzone: Double,
        layout: PadZoneLayout = .radialFour
    ) -> Set<ButtonZone> {
        let fx = Double(x) / 32_768.0
        let fy = Double(y) / 32_768.0
        switch layout {
        case .radialFour:
            let magnitude = (fx * fx + fy * fy).squareRoot()
            guard magnitude > deadzone else { return [] }
            let angle = atan2(fy, fx) * 180 / .pi
            if angle >= -45, angle < 45 { return [.right] }
            if angle >= 45, angle < 135 { return [.up] }
            if angle >= -135, angle < -45 { return [.down] }
            return [.left]
        case .fourCorners:
            guard (fx * fx + fy * fy).squareRoot() > deadzone else { return [] }
            if fx < 0, fy >= 0 { return [.topLeft] }
            if fx >= 0, fy >= 0 { return [.topRight] }
            if fx >= 0, fy < 0 { return [.bottomRight] }
            return [.bottomLeft]
        case .horizontalTwo:
            guard abs(fx) > deadzone else { return [] }
            return fx < 0 ? [.left] : [.right]
        case .verticalTwo:
            guard abs(fy) > deadzone else { return [] }
            return fy < 0 ? [.down] : [.up]
        case .gridNine:
            let column = fx < -1.0 / 3.0 ? -1 : (fx > 1.0 / 3.0 ? 1 : 0)
            let row = fy < -1.0 / 3.0 ? -1 : (fy > 1.0 / 3.0 ? 1 : 0)
            switch (row, column) {
            case (1, -1): return [.topLeft]
            case (1, 0): return [.up]
            case (1, 1): return [.topRight]
            case (0, -1): return [.left]
            case (0, 0): return [.center]
            case (0, 1): return [.right]
            case (-1, -1): return [.bottomLeft]
            case (-1, 0): return [.down]
            default: return [.bottomRight]
            }
        }
    }

    private mutating func updateTapEligibility(with sample: TrackpadSample) {
        guard sample.isTouched, tapEligible, let origin = tapOrigin else { return }
        let dx = Double(Int(sample.x) - Int(origin.x))
        let dy = Double(Int(sample.y) - Int(origin.y))
        let usesCenterTapZone = configuration.mode == .mouse && configuration.mouseDeadzone > 0
        let movedTooFar = !usesCenterTapZone
            && (dx * dx + dy * dy).squareRoot() > configuration.tapMaximumMovement
        let leftMouseTapZone = configuration.mode == .mouse
            && configuration.mouseDeadzone > 0
            && !Self.isInsideMouseDeadzone(sample, deadzone: configuration.mouseDeadzone)
        if movedTooFar || leftMouseTapZone {
            tapEligible = false
        }
    }

    private mutating func updateButtonZones(to next: Set<ButtonZone>) throws -> [TrackpadOutputAction] {
        guard next != activeZones else { return [] }
        var actions: [TrackpadOutputAction] = []
        for zone in activeZones.subtracting(next).sorted(by: { Self.sortOrder($0) < Self.sortOrder($1) }) {
            actions.append(try outputAction(for: zone, isPressed: false))
        }
        for zone in next.subtracting(activeZones).sorted(by: { Self.sortOrder($0) < Self.sortOrder($1) }) {
            actions.append(try outputAction(for: zone, isPressed: true))
        }
        activeZones = next
        return actions
    }

    private func binding(for zone: ButtonZone) -> String {
        if configuration.zoneLayout == .gridNine {
            switch zone {
            case .topLeft: return configuration.gridKeys.topLeft
            case .up: return configuration.gridKeys.top
            case .topRight: return configuration.gridKeys.topRight
            case .left: return configuration.gridKeys.left
            case .center: return configuration.gridKeys.center
            case .right: return configuration.gridKeys.right
            case .bottomLeft: return configuration.gridKeys.bottomLeft
            case .down: return configuration.gridKeys.bottom
            case .bottomRight: return configuration.gridKeys.bottomRight
            }
        }
        switch zone {
        case .topLeft, .up: return configuration.dpadKeys.up
        case .topRight, .right: return configuration.dpadKeys.right
        case .bottomRight, .down: return configuration.dpadKeys.down
        case .bottomLeft, .left: return configuration.dpadKeys.left
        case .center: return configuration.gridKeys.center
        }
    }

    private func outputAction(for zone: ButtonZone, isPressed: Bool) throws -> TrackpadOutputAction {
        try outputAction(for: binding(for: zone), isPressed: isPressed)
    }

    private func outputAction(for binding: String, isPressed: Bool) throws -> TrackpadOutputAction {
        switch binding {
        case TapBindingCatalog.leftMouseButton:
            return .mouseButton(.left, isPressed: isPressed)
        case TapBindingCatalog.rightMouseButton:
            return .mouseButton(.right, isPressed: isPressed)
        default:
            return .key(try KeyCatalog.resolve(binding), isPressed: isPressed)
        }
    }

    private func tapActions(for binding: String) throws -> [TrackpadOutputAction] {
        [
            try outputAction(for: binding, isPressed: true),
            try outputAction(for: binding, isPressed: false)
        ]
    }

    private static func isInsideMouseDeadzone(_ sample: TrackpadSample, deadzone: Double) -> Bool {
        guard deadzone > 0 else { return false }
        let x = Double(sample.x) / 32_768.0
        let y = Double(sample.y) / 32_768.0
        return (x * x + y * y).squareRoot() <= deadzone
    }

    private static func sortOrder(_ zone: ButtonZone) -> Int {
        switch zone {
        case .topLeft: return 0
        case .up: return 1
        case .topRight: return 2
        case .left: return 3
        case .center: return 4
        case .right: return 5
        case .bottomLeft: return 6
        case .down: return 7
        case .bottomRight: return 8
        }
    }

}
