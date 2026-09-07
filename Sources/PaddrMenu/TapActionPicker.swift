import SwiftUI
import PaddrCore

struct TapActionPicker: View {
    @Binding var selection: String?

    var body: some View {
        PaddrSettingsRow(title: "Touch tap", systemImage: "hand.tap") {
            OptionalOutputBindingPicker(selection: $selection, title: "Touch tap action")
        }
        .help("Click a mouse button or emit a keyboard key after a short touch and release.")
    }
}

/// Native optional output menu shared by touch taps and rear buttons.
struct OptionalOutputBindingPicker: View {
    @Binding var selection: String?
    let title: LocalizedStringKey

    var customSelection: String? {
        guard let selection,
              !TapBindingCatalog.isMouseButton(selection),
              !KeyCatalog.commonNames.contains(selection)
        else { return nil }
        return selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
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
        .frame(width: PaddrStyle.Width.control, alignment: .trailing)
    }
}
