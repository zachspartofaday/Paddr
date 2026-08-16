import PaddrAppSupport
import SwiftUI

struct ConfigurationView: View {
    @Bindable var model: PaddrMenuModel
    @State private var configurationContentHeight: CGFloat = 0
    @State private var commandBarHeight = PaddrStyle.Metrics.commandBar

    var body: some View {
        ZStack {
            PanelBackgroundView()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
                        TopControlsView(model: model)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: PaddrStyle.Spacing.s3) {
                                PadConfigurationView(
                                    side: .left,
                                    configuration: $model.configuration.left
                                )
                                .frame(width: PaddrStyle.padColumnWidth)

                                PadConfigurationView(
                                    side: .right,
                                    configuration: $model.configuration.right
                                )
                                .frame(width: PaddrStyle.padColumnWidth)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: PaddrStyle.Spacing.s3) {
                                PadConfigurationView(
                                    side: .left,
                                    configuration: $model.configuration.left
                                )
                                PadConfigurationView(
                                    side: .right,
                                    configuration: $model.configuration.right
                                )
                            }
                        }
                        .disabled(!model.activeProfileControlsAppearEnabled)
                        .allowsHitTesting(model.canEditActiveProfile)
                        .accessibilityRespondsToUserInteraction(model.canEditActiveProfile)
                    }
                    .padding(PaddrStyle.Spacing.s4)
                    .onGeometryChange(
                        for: CGFloat.self,
                        of: { $0.size.height },
                        action: { measuredHeight in
                            guard measuredHeight > 0 else { return }
                            configurationContentHeight = measuredHeight
                        }
                    )
                }
                .scrollIndicators(.automatic)

                ApplyBarView(model: model)
                    .onGeometryChange(
                        for: CGFloat.self,
                        of: { $0.size.height },
                        action: { measuredHeight in
                            guard measuredHeight > 0 else { return }
                            commandBarHeight = measuredHeight
                        }
                    )
            }
        }
        .frame(
            minWidth: PaddrStyle.Metrics.minimumWindowSize.width,
            minHeight: PaddrStyle.Metrics.minimumWindowSize.height
        )
        .paddrTypography(.rowLabel)
        .controlSize(.regular)
        .tint(PaddrStyle.accent)
        .background {
            if configurationContentHeight > 0 {
                WindowContentFitter(
                    targetHeight: max(
                        PaddrStyle.Metrics.minimumWindowSize.height,
                        configurationContentHeight + commandBarHeight
                    )
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshStatus)
                    .labelStyle(.iconOnly)
                    .help("Refresh controller and permission status")

                Toggle("Trackpad output", isOn: $model.isEnabled)
                    .labelsHidden()
                    .disabled(!model.canToggleOutput)
                    .toggleStyle(.switch)
                    .accessibilityValue(
                        model.isEnabled
                            ? LocalizedStringResource("On")
                            : LocalizedStringResource("Off")
                    )
            }
        }
    }
}
