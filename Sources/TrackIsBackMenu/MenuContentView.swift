import SwiftUI

struct MenuContentView: View {
    @Bindable var model: TrackIsBackMenuModel
    let panelSize: CGSize

    var body: some View {
        ZStack {
            PanelBackgroundView()

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: TrackIsBackStyle.sectionSpacing) {
                        AppHeaderView(model: model)
                        SystemAccessView(model: model)
                        PadConfigurationView(side: .left, configuration: $model.configuration.left)
                        PadConfigurationView(side: .right, configuration: $model.configuration.right)
                    }
                    .padding(TrackIsBackStyle.panelPadding)
                }
                .scrollIndicators(.hidden)

                ApplyBarView(model: model)
                AppFooterView(model: model)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .tint(TrackIsBackStyle.accent)
    }
}
