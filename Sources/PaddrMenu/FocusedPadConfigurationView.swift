import PaddrCore
import SwiftUI

/// Owns the window-local side choice. It intentionally has no persistence seam:
/// profile changes replace the binding value while this view-local selection remains.
struct FocusedPadConfigurationView: View {
    @Binding var configuration: PaddrConfiguration
    let appearsEnabled: Bool
    let isEditable: Bool

    @State private var selection: PaddrPadSelection

    init(
        configuration: Binding<PaddrConfiguration>,
        appearsEnabled: Bool,
        isEditable: Bool,
        initialSelection: PaddrPadSelection = .left
    ) {
        _configuration = configuration
        self.appearsEnabled = appearsEnabled
        self.isEditable = isEditable
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            PadSideSelectorView(
                selection: $selection,
                leftConfiguration: configuration.left,
                rightConfiguration: configuration.right
            )

            Group {
                if selection == .left {
                    PadConfigurationView(
                        side: .left,
                        configuration: $configuration.left
                    )
                    .paddrAccessibilityID("pad-editor", "left")
                } else {
                    PadConfigurationView(
                        side: .right,
                        configuration: $configuration.right
                    )
                    .paddrAccessibilityID("pad-editor", "right")
                }
            }
            .disabled(!appearsEnabled)
            .allowsHitTesting(isEditable)
            .accessibilityRespondsToUserInteraction(isEditable)
        }
    }
}
