import SwiftUI
import TrackIsBackCore

struct TapActionPicker: View {
    @Binding var selection: String?

    private var customSelection: String? {
        guard let selection,
              !TapBindingCatalog.isMouseButton(selection),
              !KeyCatalog.commonNames.contains(selection)
        else { return nil }
        return selection
    }

    var body: some View {
        PaddrSettingsRow(title: "Touch tap", systemImage: "hand.tap") {
            Picker("Touch tap action", selection: $selection) {
                Text("None").tag(String?.none)
                if let customSelection {
                    OutputBindingText(binding: customSelection).tag(Optional(customSelection))
                }
                Divider()
                Label("Left click", systemImage: "computermouse.fill").tag(Optional(TapBindingCatalog.leftMouseButton))
                Label("Right click", systemImage: "computermouse").tag(Optional(TapBindingCatalog.rightMouseButton))
                Divider()
                ForEach(KeyCatalog.commonNames, id: \.self) { key in
                    OutputBindingText(binding: key).tag(Optional(key))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .paddrMenuSelector()
            .frame(width: PaddrStyle.compactPickerWidth, alignment: .trailing)
        }
        .help("Click a mouse button or emit a keyboard key after a short touch and release.")
    }
}
