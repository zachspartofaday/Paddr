import SwiftUI

struct ApplyBarView: View {
    @Bindable var model: TrackIsBackMenuModel

    var body: some View {
        HStack(spacing: 12) {
            Label(
                model.hasUnsavedChanges ? "Unsaved changes" : "Configuration saved",
                systemImage: model.hasUnsavedChanges ? "circle.fill" : "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(model.hasUnsavedChanges ? .orange : TrackIsBackStyle.accent)

            Spacer()

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Defaults", systemImage: "arrow.counterclockwise", action: model.restoreDefaults)
                        .buttonStyle(.glass)
                        .controlSize(.regular)

                    Button("Save & Apply", systemImage: "checkmark", action: model.saveAndApply)
                        .buttonStyle(.glassProminent)
                        .controlSize(.regular)
                        .disabled(!model.hasUnsavedChanges && !model.isEnabled)
                        .keyboardShortcut("s", modifiers: .command)
                }
            }
        }
        .padding(.horizontal, TrackIsBackStyle.panelPadding)
        .frame(height: 58)
        .background(.thickMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
