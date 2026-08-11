import PaddrAppSupport
import SwiftUI

struct ApplyBarView: View {
    @Bindable var model: PaddrMenuModel

    var body: some View {
        HStack(spacing: 12) {
            Label(
                model.hasUnsavedChanges ? "Unsaved changes" : "Saved",
                systemImage: model.hasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill"
            )
            .paddrTypography(.caption)
            .foregroundStyle(model.hasUnsavedChanges ? .orange : PaddrStyle.accent)

            Spacer()

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Defaults", systemImage: "arrow.counterclockwise", action: model.restoreDefaults)
                        .paddrActionButton()

                    Button("Save & Apply", systemImage: "checkmark", action: model.saveAndApply)
                        .paddrActionButton(prominent: true)
                        .disabled(!model.hasUnsavedChanges && !model.isEnabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, PaddrStyle.panelPadding)
        .frame(minHeight: 58)
        .background(.thickMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}
