import AppKit
import SwiftUI

struct WindowContentFitter: NSViewRepresentable {
    let targetHeight: CGFloat

    final class Coordinator {
        var lastAppliedHeight: CGFloat?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        scheduleResize(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        scheduleResize(for: view, coordinator: context.coordinator)
    }

    private func scheduleResize(for view: NSView, coordinator: Coordinator) {
        let requestedHeight = targetHeight
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let maximumHeight = window.screen?.visibleFrame.height ?? requestedHeight
            let fittedHeight = min(requestedHeight, maximumHeight)
            guard coordinator.lastAppliedHeight != fittedHeight else { return }

            let contentRect = window.contentRect(forFrameRect: window.frame)
            guard abs(contentRect.height - fittedHeight) > 0.5 else {
                coordinator.lastAppliedHeight = fittedHeight
                return
            }

            let topEdge = window.frame.maxY
            let fittedContentRect = NSRect(
                x: contentRect.minX,
                y: contentRect.minY,
                width: contentRect.width,
                height: fittedHeight
            )
            var fittedFrame = window.frameRect(forContentRect: fittedContentRect)
            fittedFrame.origin.x = window.frame.origin.x
            fittedFrame.origin.y = topEdge - fittedFrame.height
            window.setFrame(fittedFrame, display: true, animate: window.isVisible)
            coordinator.lastAppliedHeight = fittedHeight
        }
    }
}
