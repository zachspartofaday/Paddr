import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = TrackIsBackMenuModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var documentationWindow: NSWindow?
    private lazy var panelSize = TrackIsBackStyle.panelSize(for: NSScreen.main)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDocumentationPreview = CommandLine.arguments.contains("--documentation-preview")
        NSApplication.shared.setActivationPolicy(isDocumentationPreview ? .regular : .accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PuckPads"
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = panelSize
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(model: model, panelSize: panelSize)
        )

        model.statusDidChange = { [weak self] in self?.updateIcon() }
        updateIcon()

        if isDocumentationPreview {
            showDocumentationWindow()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        model.refreshStatus()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshStatus()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let waitsForKeyRelease = model.stopForTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return waitsForKeyRelease ? .terminateLater : .terminateNow
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(from: sender)
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshStatus()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let stateItem = NSMenuItem(
            title: model.isEnabled ? "Turn Trackpads Off" : "Turn Trackpads On",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        stateItem.target = self
        menu.addItem(stateItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit PuckPads", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func toggleEnabled() {
        model.isEnabled.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateIcon() {
        let symbol = model.isEnabled ? "hand.point.up.left.fill" : "hand.point.up.left"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PuckPads")
        image?.isTemplate = !model.isEnabled
        statusItem?.button?.image = image
        statusItem?.button?.contentTintColor = model.isEnabled
            ? (model.controllerConnected ? .systemBlue : .systemOrange)
            : nil
    }

    private func showDocumentationWindow() {
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: panelSize
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PuckPads"
        window.contentViewController = NSHostingController(
            rootView: MenuContentView(model: model, panelSize: panelSize)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        documentationWindow = window
    }
}
