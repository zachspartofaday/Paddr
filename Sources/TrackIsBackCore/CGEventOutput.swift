#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

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

public final class CGEventOutput {
    #if canImport(CoreGraphics)
    private let source = CGEventSource(stateID: .hidSystemState)
    #endif

    public init() {}

    public func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions {
            switch action {
            case let .mouseMove(dx, dy):
                try postMouseMove(dx: dx, dy: dy)
            case let .mouseButton(button, isPressed):
                try postMouseButton(button, isPressed: isPressed)
            case let .scroll(dx, dy):
                try postScroll(dx: dx, dy: dy)
            case let .key(key, isPressed):
                try postKey(key, isPressed: isPressed)
            }
        }
    }

    private func postMouseButton(_ button: MouseButtonBinding, isPressed: Bool) throws {
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

    private func postMouseMove(dx: Double, dy: Double) throws {
        #if canImport(CoreGraphics)
        guard dx != 0 || dy != 0, let current = CGEvent(source: nil)?.location else { return }
        let destination = CGPoint(x: current.x + dx, y: current.y + dy)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: destination,
            mouseButton: .left
        ) else { throw TrackIsBackError.output("Could not create a mouse event.") }
        event.post(tap: .cghidEventTap)
        #else
        throw TrackIsBackError.output("CoreGraphics output is unavailable.")
        #endif
    }

    private func postScroll(dx: Double, dy: Double) throws {
        #if canImport(CoreGraphics)
        guard dx != 0 || dy != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy.rounded()),
            wheel2: Int32(dx.rounded()),
            wheel3: 0
        ) else { throw TrackIsBackError.output("Could not create a scroll event.") }
        event.post(tap: .cghidEventTap)
        #else
        throw TrackIsBackError.output("CoreGraphics output is unavailable.")
        #endif
    }

    private func postKey(_ key: KeyBinding, isPressed: Bool) throws {
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
}
