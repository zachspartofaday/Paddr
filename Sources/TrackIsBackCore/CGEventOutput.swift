#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Synchronization

public enum Permissions {
    public static func accessibilityTrusted(prompt: Bool) -> Bool {
        #if canImport(ApplicationServices)
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }
}

public protocol TrackpadOutputDispatching: Sendable {
    func dispatch(_ actions: [TrackpadOutputAction]) throws
}

public final class CGEventOutput: TrackpadOutputDispatching, Sendable {
    private let heldMouseButtons = Mutex<Set<MouseButtonBinding>>([])

    public init() {}

    public func dispatch(_ actions: [TrackpadOutputAction]) throws {
        try heldMouseButtons.withLock { heldButtons in
            #if canImport(CoreGraphics)
            let source = CGEventSource(stateID: .hidSystemState)
            #endif
            for action in actions {
                switch action {
                case let .mouseMove(dx, dy):
                    try postMouseMove(dx: dx, dy: dy, heldButtons: heldButtons, source: source)
                case let .mouseButton(button, isPressed):
                    try postMouseButton(button, isPressed: isPressed, source: source)
                    if isPressed {
                        heldButtons.insert(button)
                    } else {
                        heldButtons.remove(button)
                    }
                case let .scroll(dx, dy):
                    try postScroll(dx: dx, dy: dy, source: source)
                case let .key(key, isPressed):
                    try postKey(key, isPressed: isPressed, source: source)
                }
            }
        }
    }

    private func postMouseButton(
        _ button: MouseButtonBinding,
        isPressed: Bool,
        source: CGEventSource?
    ) throws {
        #if canImport(CoreGraphics)
        guard let location = CGEvent(source: nil)?.location else { return }
        let mouseButton: CGMouseButton = button == .left ? .left : .right
        let eventType: CGEventType
        switch (button, isPressed) {
        case (.left, true): eventType = .leftMouseDown
        case (.left, false): eventType = .leftMouseUp
        case (.right, true): eventType = .rightMouseDown
        case (.right, false): eventType = .rightMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) else { throw TrackIsBackError.output("Could not create a \(button.rawValue) mouse-button event.") }
        event.post(tap: .cghidEventTap)
        #else
        throw TrackIsBackError.output("CoreGraphics output is unavailable.")
        #endif
    }

    private func postMouseMove(
        dx: Double,
        dy: Double,
        heldButtons: Set<MouseButtonBinding>,
        source: CGEventSource?
    ) throws {
        #if canImport(CoreGraphics)
        guard dx != 0 || dy != 0, let current = CGEvent(source: nil)?.location else { return }
        let destination = CGPoint(x: current.x + dx, y: current.y + dy)
        let eventType = Self.mouseMovementEventType(heldButtons: heldButtons)
        let mouseButton: CGMouseButton = heldButtons.contains(.right) && !heldButtons.contains(.left)
            ? .right
            : .left
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: destination,
            mouseButton: mouseButton
        ) else { throw TrackIsBackError.output("Could not create a mouse event.") }
        event.post(tap: .cghidEventTap)
        #else
        throw TrackIsBackError.output("CoreGraphics output is unavailable.")
        #endif
    }

    private func postScroll(dx: Double, dy: Double, source: CGEventSource?) throws {
        #if canImport(CoreGraphics)
        guard dx.isFinite, dy.isFinite else {
            throw TrackIsBackError.output("Scroll output must be finite.")
        }
        guard dx != 0 || dy != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Self.clampedScrollValue(dy),
            wheel2: Self.clampedScrollValue(dx),
            wheel3: 0
        ) else { throw TrackIsBackError.output("Could not create a scroll event.") }
        event.post(tap: .cghidEventTap)
        #else
        throw TrackIsBackError.output("CoreGraphics output is unavailable.")
        #endif
    }

    public static func clampedScrollValue(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded >= Double(Int32.max) { return Int32.max }
        if rounded <= Double(Int32.min) { return Int32.min }
        return Int32(rounded)
    }

    private func postKey(_ key: KeyBinding, isPressed: Bool, source: CGEventSource?) throws {
        #if canImport(CoreGraphics)
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(key.keyCode),
            keyDown: isPressed
        ) else { throw TrackIsBackError.output("Could not create keyboard event for \(key.name).") }
        event.post(tap: .cghidEventTap)
        #else
        throw TrackIsBackError.output("CoreGraphics output is unavailable.")
        #endif
    }

    #if canImport(CoreGraphics)
    static func mouseMovementEventType(heldButtons: Set<MouseButtonBinding>) -> CGEventType {
        if heldButtons.contains(.left) { return .leftMouseDragged }
        if heldButtons.contains(.right) { return .rightMouseDragged }
        return .mouseMoved
    }
    #endif
}
