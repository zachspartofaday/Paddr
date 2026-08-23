#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(IOKit)
import IOKit.hid
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

    /// Input Monitoring (TCC ListenEvent) covers receiving puck HID reports. The native system
    /// prompt exists only while the state is undetermined; once denied, only System Settings can
    /// re-enable it, so callers must route a denied request to Settings instead of re-prompting.
    public static func inputMonitoringAccess(requestingIfUndetermined request: Bool) -> InputMonitoringAccess {
        #if canImport(IOKit)
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            guard request else { return .undetermined }
            // The prompt is asynchronous: a false return means "answer pending", not denied.
            return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) ? .granted : .undetermined
        }
        #else
        return .denied
        #endif
    }
}

public enum InputMonitoringAccess: Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

public protocol TrackpadOutputDispatching: Sendable {
    func dispatch(_ actions: [TrackpadOutputAction]) throws
}

#if canImport(CoreGraphics)
enum CGEventRequest: Equatable, Sendable {
    enum MouseKind: Equatable, Sendable {
        case moved
        case leftDragged
        case rightDragged
        case leftDown
        case leftUp
        case rightDown
        case rightUp
    }

    case mouse(kind: MouseKind, button: MouseButtonBinding, x: Double, y: Double)
    case scroll(horizontal: Int32, vertical: Int32)
    case key(code: UInt16, isPressed: Bool)
}
#endif

public final class CGEventOutput: TrackpadOutputDispatching, Sendable {
    private let heldMouseButtons = Mutex<Set<MouseButtonBinding>>([])
    #if canImport(CoreGraphics)
    private let currentMouseLocation: @Sendable () -> CGPoint?
    private let postEvent: @Sendable (CGEventRequest) throws -> Void
    #endif

    public init() {
        #if canImport(CoreGraphics)
        currentMouseLocation = { CGEvent(source: nil)?.location }
        postEvent = Self.postLiveEvent
        #endif
    }

    #if canImport(CoreGraphics)
    init(currentMouseLocation: @escaping @Sendable () -> CGPoint?) {
        self.currentMouseLocation = currentMouseLocation
        postEvent = Self.postLiveEvent
    }

    init(
        currentMouseLocation: @escaping @Sendable () -> CGPoint?,
        postEvent: @escaping @Sendable (CGEventRequest) throws -> Void
    ) {
        self.currentMouseLocation = currentMouseLocation
        self.postEvent = postEvent
    }
    #endif

    public func dispatch(_ actions: [TrackpadOutputAction]) throws {
        try heldMouseButtons.withLock { heldButtons in
            for action in actions {
                switch action {
                case let .mouseMove(dx, dy):
                    try postMouseMove(dx: dx, dy: dy, heldButtons: heldButtons)
                case let .mouseButton(button, isPressed):
                    try postMouseButton(button, isPressed: isPressed)
                    if isPressed {
                        heldButtons.insert(button)
                    } else {
                        heldButtons.remove(button)
                    }
                case let .scroll(dx, dy):
                    try postScroll(dx: dx, dy: dy)
                case let .key(key, isPressed):
                    try postKey(key, isPressed: isPressed)
                }
            }
        }
    }

    private func postMouseButton(
        _ button: MouseButtonBinding,
        isPressed: Bool
    ) throws {
        #if canImport(CoreGraphics)
        guard let location = currentMouseLocation() else {
            let transition = isPressed ? "down" : "up"
            throw PaddrError.output(
                "Could not determine the mouse location for a \(button.rawValue) mouse-button \(transition) event."
            )
        }
        let kind: CGEventRequest.MouseKind
        switch (button, isPressed) {
        case (.left, true): kind = .leftDown
        case (.left, false): kind = .leftUp
        case (.right, true): kind = .rightDown
        case (.right, false): kind = .rightUp
        }
        try postEvent(.mouse(
            kind: kind,
            button: button,
            x: location.x,
            y: location.y
        ))
        #else
        throw PaddrError.output("CoreGraphics output is unavailable.")
        #endif
    }

    private func postMouseMove(
        dx: Double,
        dy: Double,
        heldButtons: Set<MouseButtonBinding>
    ) throws {
        #if canImport(CoreGraphics)
        guard dx != 0 || dy != 0, let current = currentMouseLocation() else { return }
        let destination = CGPoint(x: current.x + dx, y: current.y + dy)
        let kind = Self.mouseMovementKind(heldButtons: heldButtons)
        let button: MouseButtonBinding = heldButtons.contains(.right) && !heldButtons.contains(.left)
            ? .right
            : .left
        try postEvent(.mouse(
            kind: kind,
            button: button,
            x: destination.x,
            y: destination.y
        ))
        #else
        throw PaddrError.output("CoreGraphics output is unavailable.")
        #endif
    }

    private func postScroll(dx: Double, dy: Double) throws {
        #if canImport(CoreGraphics)
        guard dx.isFinite, dy.isFinite else {
            throw PaddrError.output("Scroll output must be finite.")
        }
        guard dx != 0 || dy != 0 else { return }
        try postEvent(.scroll(
            horizontal: Self.clampedScrollValue(dx),
            vertical: Self.clampedScrollValue(dy)
        ))
        #else
        throw PaddrError.output("CoreGraphics output is unavailable.")
        #endif
    }

    public static func clampedScrollValue(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded >= Double(Int32.max) { return Int32.max }
        if rounded <= Double(Int32.min) { return Int32.min }
        return Int32(rounded)
    }

    private func postKey(_ key: KeyBinding, isPressed: Bool) throws {
        #if canImport(CoreGraphics)
        try postEvent(.key(code: key.keyCode, isPressed: isPressed))
        #else
        throw PaddrError.output("CoreGraphics output is unavailable.")
        #endif
    }

    #if canImport(CoreGraphics)
    static func mouseMovementKind(
        heldButtons: Set<MouseButtonBinding>
    ) -> CGEventRequest.MouseKind {
        if heldButtons.contains(.left) { return .leftDragged }
        if heldButtons.contains(.right) { return .rightDragged }
        return .moved
    }

    private static func postLiveEvent(_ request: CGEventRequest) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let event: CGEvent?
        switch request {
        case let .mouse(kind, button, x, y):
            let eventType: CGEventType
            switch kind {
            case .moved: eventType = .mouseMoved
            case .leftDragged: eventType = .leftMouseDragged
            case .rightDragged: eventType = .rightMouseDragged
            case .leftDown: eventType = .leftMouseDown
            case .leftUp: eventType = .leftMouseUp
            case .rightDown: eventType = .rightMouseDown
            case .rightUp: eventType = .rightMouseUp
            }
            event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: button == .left ? .left : .right
            )
        case let .scroll(horizontal, vertical):
            event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: vertical,
                wheel2: horizontal,
                wheel3: 0
            )
        case let .key(code, isPressed):
            event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(code),
                keyDown: isPressed
            )
        }
        guard let event else { throw PaddrError.output("Could not create a CGEvent output event.") }
        event.post(tap: .cghidEventTap)
    }
    #endif
}
