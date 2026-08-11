import AppKit
import SwiftUI

struct AppFooterView: View {
    @Bindable var model: TrackIsBackMenuModel

    var body: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise", action: model.refreshStatus)
                .buttonStyle(.glass)
            Spacer()
            Label("Puck mode · passive HID", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit", systemImage: "power", action: quit)
                .buttonStyle(.glass)
        }
        .font(.caption)
        .padding(.horizontal, TrackIsBackStyle.panelPadding)
        .frame(height: 38)
        .background(.ultraThinMaterial)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
