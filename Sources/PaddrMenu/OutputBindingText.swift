import SwiftUI
import PaddrCore

struct OutputBindingText: View {
    let binding: String

    var body: some View {
        Self.text(for: binding)
    }

    static func text(for binding: String) -> Text {
        if let localizedName = OutputBindingPresentation.localizedName(for: binding) {
            return Text(localizedName)
        } else {
            return Text(verbatim: OutputBindingPresentation.verbatimName(for: binding))
        }
    }
}
