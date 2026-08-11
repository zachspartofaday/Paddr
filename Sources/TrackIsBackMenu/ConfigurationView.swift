import PaddrAppSupport
import SwiftUI

struct ConfigurationView: View {
    @Bindable var model: PaddrMenuModel
    @State private var configurationContentHeight: CGFloat = 0

    var body: some View {
        ZStack {
            PanelBackgroundView()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: PaddrStyle.sectionSpacing) {
                        AppHeaderView(model: model)
                        if !model.hasSystemAccess { SystemAccessView(model: model) }
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: PaddrStyle.sectionSpacing) {
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

                            VStack(spacing: PaddrStyle.sectionSpacing) {
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
                    }
                    .padding(PaddrStyle.panelPadding)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ConfigurationContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                }
                .scrollIndicators(.automatic)

                ApplyBarView(model: model)
            }
        }
        .frame(
            minWidth: PaddrStyle.minimumWindowSize.width,
            minHeight: PaddrStyle.minimumWindowSize.height
        )
        .paddrTypography(.callout)
        .controlSize(.regular)
        .tint(PaddrStyle.accent)
        .background {
            WindowContentFitter(
                targetHeight: max(
                    PaddrStyle.minimumWindowSize.height,
                    configurationContentHeight + 50
                )
            )
        }
        .onPreferenceChange(ConfigurationContentHeightKey.self) { configurationContentHeight = $0 }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshStatus)
                    .labelStyle(.iconOnly)
                    .help("Refresh controller and permission status")

                Toggle("Trackpad output", isOn: $model.isEnabled)
                    .labelsHidden()
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

private struct ConfigurationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
