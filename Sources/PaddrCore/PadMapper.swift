import Foundation

public enum DPadDirection: String, CaseIterable, Hashable, Sendable {
    case up
    case right
    case down
    case left
}

private struct PointerMotionFilter: Sendable {
    private static let rawUnitsPerPoint = 700.0
    private static let derivativeCutoffHz = 1.0
    private static let speedCoefficient = 0.08
    private static let longestIntervalNanoseconds: UInt64 = 100_000_000

    private var filteredX: Double?
    private var filteredY: Double?
    private var filteredDerivativeX = 0.0
    private var filteredDerivativeY = 0.0
    private var rawX: Double?
    private var rawY: Double?
    private var timestamp: UInt64?

    mutating func reset(anchor: TrackpadSample? = nil) {
        guard let anchor else {
            filteredX = nil
            filteredY = nil
            filteredDerivativeX = 0
            filteredDerivativeY = 0
            rawX = nil
            rawY = nil
            timestamp = nil
            return
        }
        let x = Double(anchor.x)
        let y = Double(anchor.y)
        filteredX = x
        filteredY = y
        filteredDerivativeX = 0
        filteredDerivativeY = 0
        rawX = x
        rawY = y
        timestamp = anchor.timestampNanoseconds
    }

    mutating func filteredDelta(
        to sample: TrackpadSample,
        strength: Double
    ) -> (dx: Double, dy: Double, previousTimestamp: UInt64)? {
        guard let previousTimestamp = timestamp,
              let previousRawX = rawX,
              let previousRawY = rawY,
              let previousFilteredX = filteredX,
              let previousFilteredY = filteredY,
              sample.timestampNanoseconds > previousTimestamp,
              sample.timestampNanoseconds - previousTimestamp <= Self.longestIntervalNanoseconds
        else {
            reset(anchor: sample)
            return nil
        }

        let intervalNanoseconds = sample.timestampNanoseconds - previousTimestamp
        let intervalSeconds = Double(intervalNanoseconds) / 1_000_000_000
        let nextRawX = Double(sample.x)
        let nextRawY = Double(sample.y)
        let derivativeAlpha = Self.alpha(
            cutoffHz: Self.derivativeCutoffHz,
            intervalSeconds: intervalSeconds
        )
        filteredDerivativeX = Self.lowPass(
            value: (nextRawX - previousRawX) / Self.rawUnitsPerPoint / intervalSeconds,
            previous: filteredDerivativeX,
            alpha: derivativeAlpha
        )
        filteredDerivativeY = Self.lowPass(
            value: (nextRawY - previousRawY) / Self.rawUnitsPerPoint / intervalSeconds,
            previous: filteredDerivativeY,
            alpha: derivativeAlpha
        )

        let boundedStrength = min(max(strength, 0), 1)
        let minimumCutoffHz = 20 - 19 * boundedStrength
        let nextFilteredX = Self.lowPass(
            value: nextRawX,
            previous: previousFilteredX,
            alpha: Self.alpha(
                cutoffHz: minimumCutoffHz
                    + Self.speedCoefficient * abs(filteredDerivativeX),
                intervalSeconds: intervalSeconds
            )
        )
        let nextFilteredY = Self.lowPass(
            value: nextRawY,
            previous: previousFilteredY,
            alpha: Self.alpha(
                cutoffHz: minimumCutoffHz
                    + Self.speedCoefficient * abs(filteredDerivativeY),
                intervalSeconds: intervalSeconds
            )
        )

        filteredX = nextFilteredX
        filteredY = nextFilteredY
        rawX = nextRawX
        rawY = nextRawY
        timestamp = sample.timestampNanoseconds
        return (
            dx: nextFilteredX - previousFilteredX,
            dy: nextFilteredY - previousFilteredY,
            previousTimestamp: previousTimestamp
        )
    }

    private static func alpha(cutoffHz: Double, intervalSeconds: Double) -> Double {
        let timeConstant = 1 / (2 * Double.pi * cutoffHz)
        return 1 / (1 + timeConstant / intervalSeconds)
    }

    private static func lowPass(value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
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

    // Raw pad units per second. Below the low speed the pointer stays linear;
    // at or above the high speed the configured gain reaches its bounded maximum.
    private static let mouseAccelerationLowSpeed = 20_000.0
    private static let mouseAccelerationHighSpeed = 120_000.0
    private static let mouseAccelerationMinimumGain = 1.0
    private static let mouseAccelerationMaximumGain = 4.0
    private static let mouseRawUnitsPerPoint = 700.0
    // A 100 ms pause starts a fresh motion sequence instead of amplifying resumed movement.
    private static let mouseAccelerationLongGapNanoseconds: UInt64 = 100_000_000

    private var previous: TrackpadSample?
    private var activeZones: Set<ButtonZone> = []
    private var tapOrigin: (x: Int16, y: Int16, timestamp: UInt64)?
    private var tapEligible = false
    private var tapStabilizing = false
    private var pointerFilter = PointerMotionFilter()

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
            tapStabilizing = configuration.mode == .mouse
                && configuration.tapKey != nil
                && configuration.tapStabilizationEnabled
                && tapEligible
        }
        if configuration.mode == .mouse, sample.isTouched, !wasTouched {
            pointerFilter.reset(anchor: sample)
        }
        let wasTapStabilizing = tapStabilizing
        updateTapEligibility(with: sample)

        switch configuration.mode {
        case .disabled:
            actions += try updateButtonZones(to: [])
        case .mouse:
            if sample.isTouched,
               let previous,
               previous.isTouched {
                if tapStabilizing {
                    // Keep the filter anchored at touch-down so lift jitter never reaches the cursor.
                } else if wasTapStabilizing {
                    // Discard the configured movement slop and begin normal tracking from here.
                    pointerFilter.reset(anchor: sample)
                } else if shouldTrackMouse(from: previous, to: sample) {
                    if configuration.pointerSmoothingEnabled,
                       configuration.pointerSmoothingStrength > 0 {
                        if let delta = pointerFilter.filteredDelta(
                            to: sample,
                            strength: configuration.pointerSmoothingStrength
                        ) {
                            actions += mouseMoveActions(
                                rawDX: delta.dx,
                                rawDY: delta.dy,
                                previousTimestamp: delta.previousTimestamp,
                                timestamp: sample.timestampNanoseconds
                            )
                        }
                    } else {
                        actions += mouseMoveActions(
                            rawDX: Double(Int(sample.x) - Int(previous.x)),
                            rawDY: Double(Int(sample.y) - Int(previous.y)),
                            previousTimestamp: previous.timestampNanoseconds,
                            timestamp: sample.timestampNanoseconds
                        )
                    }
                } else {
                    pointerFilter.reset(anchor: sample)
                }
            }
        case .scroll:
            if sample.isTouched, let previous, previous.isTouched {
                let dx = Double(Int(sample.x) - Int(previous.x)) / 240.0 * configuration.scrollSensitivity
                let dy = -Double(Int(sample.y) - Int(previous.y)) / 240.0 * configuration.scrollSensitivity
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
            tapStabilizing = false
            pointerFilter.reset()
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
            tapStabilizing = false
            pointerFilter.reset()
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
        let elapsed = sample.timestampNanoseconds >= origin.timestamp
            ? sample.timestampNanoseconds - origin.timestamp
            : UInt64.max
        let maximumMilliseconds = min(
            max(configuration.tapMaximumMilliseconds, ConfigurationLimits.tapMaximumMilliseconds.lowerBound),
            ConfigurationLimits.tapMaximumMilliseconds.upperBound
        )
        let timedOut = elapsed > UInt64(maximumMilliseconds * 1_000_000)
        let usesCenterTapZone = configuration.mode == .mouse && configuration.mouseDeadzone > 0
        let rawDistance = hypot(dx, dy)
        let stabilizationDistance = rawDistance
            / Self.mouseRawUnitsPerPoint
            * configuration.sensitivity
        let exceededStabilizationThreshold = tapStabilizing
            && stabilizationDistance > configuration.tapStabilizationThresholdPoints
        let movedTooFar = !tapStabilizing
            && !usesCenterTapZone
            && rawDistance > configuration.tapMaximumMovement
        let leftMouseTapZone = configuration.mode == .mouse
            && configuration.mouseDeadzone > 0
            && !Self.isInsideMouseDeadzone(sample, deadzone: configuration.mouseDeadzone)
        if timedOut || exceededStabilizationThreshold || movedTooFar || leftMouseTapZone {
            tapEligible = false
            tapStabilizing = false
        }
    }

    private func mouseMoveActions(
        rawDX: Double,
        rawDY: Double,
        previousTimestamp: UInt64,
        timestamp: UInt64
    ) -> [TrackpadOutputAction] {
        let gain = Self.mouseAccelerationGain(
            rawDX: rawDX,
            rawDY: rawDY,
            previousTimestamp: previousTimestamp,
            timestamp: timestamp,
            amount: configuration.mouseAcceleration
        )
        let dx = rawDX / Self.mouseRawUnitsPerPoint * gain * configuration.sensitivity
        let dy = -rawDY / Self.mouseRawUnitsPerPoint * gain * configuration.sensitivity
        guard abs(dx) >= 0.05 || abs(dy) >= 0.05 else { return [] }
        return [.mouseMove(dx: dx, dy: dy)]
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

    private func shouldTrackMouse(from previous: TrackpadSample, to sample: TrackpadSample) -> Bool {
        switch configuration.centerTapTrackingMode {
        case .coupled:
            !Self.isInsideMouseDeadzone(sample, deadzone: configuration.mouseDeadzone)
                && !Self.isInsideMouseDeadzone(previous, deadzone: configuration.mouseDeadzone)
        case .decoupled:
            true
        }
    }

    private static func mouseAccelerationGain(
        rawDX: Double,
        rawDY: Double,
        previousTimestamp: UInt64,
        timestamp: UInt64,
        amount: Double
    ) -> Double {
        guard timestamp > previousTimestamp else { return mouseAccelerationMinimumGain }
        let intervalNanoseconds = timestamp - previousTimestamp
        guard intervalNanoseconds <= mouseAccelerationLongGapNanoseconds else {
            return mouseAccelerationMinimumGain
        }

        let intervalSeconds = Double(intervalNanoseconds) / 1_000_000_000
        let speed = hypot(rawDX, rawDY) / intervalSeconds
        let normalizedSpeed = min(
            max(
                (speed - mouseAccelerationLowSpeed)
                    / (mouseAccelerationHighSpeed - mouseAccelerationLowSpeed),
                0
            ),
            1
        )
        let smoothstep = normalizedSpeed * normalizedSpeed * (3 - 2 * normalizedSpeed)
        return mouseAccelerationMinimumGain
            + amount * (mouseAccelerationMaximumGain - mouseAccelerationMinimumGain) * smoothstep
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
