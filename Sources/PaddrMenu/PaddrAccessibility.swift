import Foundation
import SwiftUI

/// Stable, nonlocalized identifiers for VoiceOver diagnostics and UI automation.
///
/// Components must describe product UI only. Never include a controller serial number,
/// local path, profile name, or other user/runtime value.
enum PaddrAccessibility {
    static let prefix = "paddr"

    static func identifier(_ components: String...) -> String {
        identifier(components)
    }

    static func identifier(_ components: [String]) -> String {
        ([prefix] + components.map(slug).filter { !$0.isEmpty }).joined(separator: ".")
    }

    static func slug(_ rawValue: String) -> String {
        let lowercased = rawValue.lowercased()
        var result = ""
        var previousWasSeparator = false

        for scalar in lowercased.unicodeScalars {
            let value = scalar.value
            let isLowercaseLetter = value >= 97 && value <= 122
            let isDigit = value >= 48 && value <= 57
            if isLowercaseLetter || isDigit {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct PaddrOptionalAccessibilityIdentifierModifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier, !identifier.isEmpty {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

extension View {
    func paddrAccessibilityID(_ components: String...) -> some View {
        accessibilityIdentifier(PaddrAccessibility.identifier(components))
    }

    func paddrAccessibilityID(_ components: [String]) -> some View {
        accessibilityIdentifier(PaddrAccessibility.identifier(components))
    }

    func paddrOptionalAccessibilityID(_ identifier: String?) -> some View {
        modifier(PaddrOptionalAccessibilityIdentifierModifier(identifier: identifier))
    }
}
