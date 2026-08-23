import PaddrCore
import SwiftUI

/// Keeps both trackpad editors mounted together. The adaptive layout moves the
/// same two subtrees between columns and rows without duplicating editor state.
struct DualPadConfigurationView: View {
    @Binding var configuration: PaddrConfiguration
    let appearsEnabled: Bool
    let isEditable: Bool

    var body: some View {
        PaddrAdaptiveSplitView(
            equalHeightColumnsBreakpoint: PaddrStyle.Metrics.padEditorColumnsBreakpoint,
            leading: {
                PadConfigurationView(
                    side: .left,
                    configuration: $configuration.left
                )
                .paddrAccessibilityID("pad-editor", "left")
            },
            trailing: {
                PadConfigurationView(
                    side: .right,
                    configuration: $configuration.right
                )
                .paddrAccessibilityID("pad-editor", "right")
            }
        )
        .disabled(!appearsEnabled)
        .allowsHitTesting(isEditable)
        .accessibilityRespondsToUserInteraction(isEditable)
    }
}
