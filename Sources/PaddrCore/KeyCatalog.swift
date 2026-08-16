import Foundation

public struct KeyBinding: Equatable, Hashable, Sendable {
    public let name: String
    public let keyCode: UInt16
}

public enum KeyCatalog {
    private static let namedCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
        "backspace": 51, "escape": 53, "esc": 53, "command": 55, "cmd": 55,
        "shift": 56, "capslock": 57, "option": 58, "alt": 58, "control": 59,
        "ctrl": 59, "left": 123, "right": 124, "down": 125, "up": 126
    ]

    public static let commonNames: [String] = [
        "up", "right", "down", "left", "space", "return", "tab", "escape", "delete",
        "shift", "control", "option", "command",
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
    ]

    public static func resolve(_ rawName: String) throws -> KeyBinding {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("code:"), let code = UInt16(name.dropFirst(5)) {
            return KeyBinding(name: "code:\(code)", keyCode: code)
        }
        guard let keyCode = namedCodes[name] else {
            throw PaddrError.configuration(
                "Unknown key '\(rawName)'. Use a letter, digit, arrow name, space, return, tab, escape, shift, control, option, command, or code:N."
            )
        }
        return KeyBinding(name: canonicalName(for: keyCode, fallback: name), keyCode: keyCode)
    }

    private static func canonicalName(for keyCode: UInt16, fallback: String) -> String {
        switch keyCode {
        case 36: return "return"
        case 51: return "delete"
        case 53: return "escape"
        case 55: return "command"
        case 56: return "shift"
        case 58: return "option"
        case 59: return "control"
        default: return fallback
        }
    }
}

public enum OutputBindingPresentation {
    public static func localizedName(for binding: String) -> LocalizedStringResource? {
        switch binding {
        case TapBindingCatalog.leftMouseButton: LocalizedStringResource("Left click")
        case TapBindingCatalog.rightMouseButton: LocalizedStringResource("Right click")
        case "up": LocalizedStringResource("Up arrow")
        case "right": LocalizedStringResource("Right arrow")
        case "down": LocalizedStringResource("Down arrow")
        case "left": LocalizedStringResource("Left arrow")
        case "space": LocalizedStringResource("Space")
        case "return": LocalizedStringResource("Return")
        case "tab": LocalizedStringResource("Tab")
        case "escape": LocalizedStringResource("Escape")
        case "delete": LocalizedStringResource("Delete")
        case "shift": LocalizedStringResource("Shift")
        case "control": LocalizedStringResource("Control")
        case "option": LocalizedStringResource("Option")
        case "command": LocalizedStringResource("Command")
        default: nil
        }
    }

    public static func verbatimName(for binding: String) -> String {
        binding.hasPrefix("code:") ? binding : binding.uppercased()
    }
}
