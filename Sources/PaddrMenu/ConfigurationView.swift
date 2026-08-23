import PaddrAppSupport
import SwiftUI

struct ConfigurationView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        ZStack {
            PanelBackgroundView()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PaddrStyle.cardSpacing) {
                        TopControlsView(model: model)
                        DualPadConfigurationView(
                            configuration: $model.configuration,
                            appearsEnabled: model.activeProfileControlsAppearEnabled,
                            isEditable: model.canEditActiveProfile
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PaddrStyle.Inset.window)
                }
                .scrollIndicators(.automatic)

                ApplyBarView(model: model)
            }
        }
        .frame(
            minWidth: PaddrStyle.Metrics.minimumWindowSize.width,
            minHeight: PaddrStyle.Metrics.minimumWindowSize.height
        )
        .paddrTypography(.rowLabel)
        .foregroundStyle(PaddrStyle.textPrimary)
        .controlSize(.large)
        .tint(PaddrStyle.controlTint)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarSpacer(.flexible)

            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshStatus)
                    .labelStyle(.iconOnly)
                    .help("Refresh controller and permission status")
                    .paddrAccessibilityID("toolbar", "refresh")
            }
        }
    }
}
