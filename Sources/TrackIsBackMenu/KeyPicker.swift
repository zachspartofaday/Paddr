import SwiftUI
import TrackIsBackCore

struct OutputBindingPicker: View {
    @Binding var selection: String
    var width: CGFloat = 132

    private var keyChoices: [String] {
        if TapBindingCatalog.isMouseButton(selection) || KeyCatalog.commonNames.contains(selection) {
            return KeyCatalog.commonNames
        }
        return [selection] + KeyCatalog.commonNames
    }

    var body: some View {
        Picker("Action", selection: $selection) {
            Label("Left click", systemImage: "computermouse.fill")
                .tag(TapBindingCatalog.leftMouseButton)
            Label("Right click", systemImage: "computermouse")
                .tag(TapBindingCatalog.rightMouseButton)
            Divider()
            ForEach(keyChoices, id: \.self) { key in
                Text(key.capitalized).tag(key)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.regular)
        .frame(width: width)
        .accessibilityLabel("Zone action")
        .help("Assign a keyboard key, left click, or right click to this touch area.")
    }
}
