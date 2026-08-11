import PaddrAppSupport
import SwiftUI

struct ConfigurationView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        ZStack {
            PanelBackgroundView()

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PaddrStyle.sectionSpacing) {
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
    }
}
