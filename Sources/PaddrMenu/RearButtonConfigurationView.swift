import PaddrCore
import SwiftUI

struct RearButtonConfigurationView: View {
    @Binding var configuration: RearButtonConfiguration
    let isEditable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            Text("Rear buttons")
                .paddrTypography(.cardTitle)
                .foregroundStyle(PaddrStyle.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Choose an action for each rear button. Save & Apply to use your changes.")
                .paddrTypography(.rowLabel)
            Text("The action stays pressed while you hold the rear button.")
                .paddrTypography(.rowLabel)
            PaddrAdaptiveSplitView(
                equalHeightColumnsBreakpoint: PaddrStyle.Metrics.padEditorColumnsBreakpoint,
                leading: {
                    PaddrSectionContainer {
                        PaddrSettingsGroup {
                            PaddrSectionHeader("Left")
                            rearRow("L4", title: "Left rear button L4 action", selection: $configuration.l4)
                            rearRow("L5", title: "Left rear button L5 action", selection: $configuration.l5)
                        }
                    }
                },
                trailing: {
                    PaddrSectionContainer {
                        PaddrSettingsGroup {
                            PaddrSectionHeader("Right")
                            rearRow("R4", title: "Right rear button R4 action", selection: $configuration.r4)
                            rearRow("R5", title: "Right rear button R5 action", selection: $configuration.r5)
                        }
                    }
                }
            )
            .disabled(!isEditable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
        .paddrAccessibilityID("rear-buttons")
    }

    private func rearRow(
        _ code: LocalizedStringResource,
        title: LocalizedStringKey,
        selection: Binding<String?>
    ) -> some View {
        PaddrSettingsRow(title: code, systemImage: "gamecontroller") {
            OptionalOutputBindingPicker(selection: selection, title: title)
        }
    }
}
