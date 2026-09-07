import PaddrAppSupport
import SwiftUI

/// The complete scroll document, kept as one production surface so rendered layout tests
/// can measure card enclosure independently from AppKit's scroll-view implementation.
struct ConfigurationContentView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.cardSpacing) {
            TopControlsView(model: model)
            DualPadConfigurationView(
                configuration: $model.configuration,
                appearsEnabled: model.activeProfileControlsAppearEnabled,
                isEditable: model.canEditActiveProfile
            )
            RearButtonConfigurationView(
                configuration: $model.configuration.rearButtons,
                isEditable: model.canEditActiveProfile
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PaddrStyle.Inset.window)
    }
}
