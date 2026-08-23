import PaddrCore
import SwiftUI

enum PaddrPadSelection: String, CaseIterable, Hashable {
    case left
    case right

    var side: PadSide {
        switch self {
        case .left: .left
        case .right: .right
        }
    }
}

struct PadSelectorPresentation: Equatable {
    let leftTitle: String
    let rightTitle: String

    init(left: PadConfiguration, right: PadConfiguration) {
        let leftSummary = Self.summary(for: left)
        let rightSummary = Self.summary(for: right)
        leftTitle = String(
            localized: "Left · \(leftSummary)",
            comment: "Left trackpad selector option followed by its current mode"
        )
        rightTitle = String(
            localized: "Right · \(rightSummary)",
            comment: "Right trackpad selector option followed by its current mode"
        )
    }

    func title(for selection: PaddrPadSelection) -> String {
        selection == .left ? leftTitle : rightTitle
    }

    private static func summary(for configuration: PadConfiguration) -> String {
        switch configuration.mode {
        case .disabled:
            String(localized: "Off")
        case .mouse:
            String(localized: "Pointer")
        case .scroll:
            String(localized: "Scroll")
        case .dpad:
            String(localized: configuration.zoneLayout.displayName)
        }
    }
}

struct PadSideSelectorView: View {
    @Binding var selection: PaddrPadSelection
    let leftConfiguration: PadConfiguration
    let rightConfiguration: PadConfiguration

    var body: some View {
        let presentation = PadSelectorPresentation(
            left: leftConfiguration,
            right: rightConfiguration
        )
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s2) {
            Text("Trackpad")
                .paddrTypography(.sectionLabel)
                .foregroundStyle(PaddrStyle.textSecondary)

            Picker("Trackpad side", selection: $selection) {
                Text(verbatim: presentation.leftTitle).tag(PaddrPadSelection.left)
                Text(verbatim: presentation.rightTitle).tag(PaddrPadSelection.right)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .tint(PaddrStyle.controlTint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: PaddrStyle.Metrics.controlHeight)
            .accessibilityLabel("Trackpad side")
            .accessibilityValue(Text(verbatim: presentation.title(for: selection)))
            .accessibilityHint("Choose the trackpad whose settings are shown below.")
            .paddrAccessibilityID("pad-selector")
        }
        .padding(PaddrStyle.Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
    }
}
