import AppKit
import PaddrAppSupport
import SwiftUI

struct WindowContentFitter: NSViewRepresentable {
    let targetHeight: CGFloat

    @MainActor
    final class Coordinator: NSObject {
        var hasAppliedFrame = false
        var targetHeight: CGFloat = 0
        var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        weak var window: NSWindow?

        func attach(to window: NSWindow) {
            if self.window !== window {
                detach()
                self.window = window
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(screenDidChange(_:)),
                    name: NSWindow.didChangeScreenNotification,
                    object: window
                )
                NSWorkspace.shared.notificationCenter.addObserver(
                    self,
                    selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
                    name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                    object: nil
                )
            }
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            applyFrame()
        }

        func detach() {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
            NSWorkspace.shared.notificationCenter.removeObserver(
                self,
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil
            )
            window = nil
        }

        @objc private func screenDidChange(_ notification: Notification) {
            applyFrame()
        }

        @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        private func applyFrame() {
            guard let window,
                  let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            else { return }

            let contentRect = window.contentRect(forFrameRect: window.frame)
            let fittedHeight = WindowFrameGeometry.fittedContentHeight(
                requestedHeight: targetHeight,
                currentFrame: window.frame,
                currentContentRect: contentRect,
                visibleFrame: visibleFrame
            )

            let topEdge = window.frame.maxY
            let fittedContentRect = NSRect(
                x: contentRect.minX,
                y: contentRect.minY,
                width: contentRect.width,
                height: fittedHeight
            )
            let proposedFrame = window.frameRect(forContentRect: fittedContentRect)
            let fittedFrame = WindowFrameGeometry.constrainedFrame(
                proposedFrame,
                preservingTopEdge: topEdge,
                within: visibleFrame
            )
            guard !window.frame.isApproximatelyEqual(to: fittedFrame) else {
                hasAppliedFrame = true
                return
            }
            let shouldAnimate = hasAppliedFrame && window.isVisible && !reduceMotion
            window.setFrame(fittedFrame, display: true, animate: shouldAnimate)
            hasAppliedFrame = true
        }
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

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private func scheduleResize(for view: NSView, coordinator: Coordinator) {
        coordinator.targetHeight = targetHeight
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.attach(to: window)
        }
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
