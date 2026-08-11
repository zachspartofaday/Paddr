import SwiftUI
import TrackIsBackCore

struct ZoneCell: View {
    let binding: String

    private var isMouseBinding: Bool {
        TapBindingCatalog.isMouseButton(binding)
    }

    private var accessibilityTitle: String {
        switch binding {
        case TapBindingCatalog.leftMouseButton: "Left mouse button"
        case TapBindingCatalog.rightMouseButton: "Right mouse button"
        default: "Keyboard key \(binding)"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(TrackIsBackStyle.accent.opacity(0.16))
            RoundedRectangle(cornerRadius: 8)
                .stroke(TrackIsBackStyle.accent.opacity(0.25), lineWidth: 0.75)
            if isMouseBinding {
                VStack(spacing: 1) {
                    Image(systemName: "computermouse.fill")
                    Text(binding == TapBindingCatalog.leftMouseButton ? "L" : "R")
                        .font(.caption.bold())
                }
            } else {
                Text(binding.uppercased())
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }
}
