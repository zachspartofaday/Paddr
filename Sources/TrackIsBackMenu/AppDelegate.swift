import AppKit
import PaddrAppSupport
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = PaddrMenuModel()
    private let statusMenu = NSMenu()
    private var statusItem: NSStatusItem?
    private var configurationWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.menu = statusMenu
        statusMenu.delegate = self
        item.button?.toolTip = String(localized: "Paddr")

        model.statusDidChange = { [weak self] in
            self?.updateStatusItem()
        }
        updateStatusItem()
        showConfigurationWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showConfigurationWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let waitsForOutputRelease = model.stopForTermination {
            sender.reply(toApplicationShouldTerminate: true)
        }
        return waitsForOutputRelease ? .terminateLater : .terminateNow
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.refreshStatus()
        rebuildStatusMenu()
    }

    @objc private func toggleEnabled() {
        model.isEnabled.toggle()
        rebuildStatusMenu()
    }

    @objc private func openConfiguration() {
        showConfigurationWindow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let outputItem = NSMenuItem(
            title: String(localized: "Trackpad Output"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        outputItem.target = self
        outputItem.state = model.isEnabled ? .on : .off
        outputItem.image = NSImage(
            systemSymbolName: model.isEnabled ? "wave.3.right.circle.fill" : "pause.circle",
            accessibilityDescription: String(localized: "Trackpad Output")
        )
        statusMenu.addItem(outputItem)

        let configurationItem = NSMenuItem(
            title: String(localized: "Open Configuration…"),
            action: #selector(openConfiguration),
            keyEquivalent: ","
        )
        configurationItem.target = self
        configurationItem.image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: String(localized: "Open Configuration")
        )
        statusMenu.addItem(configurationItem)

        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: String(localized: "Quit Paddr"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    private func updateStatusItem() {
        let symbol = model.isEnabled ? "hand.point.up.left.fill" : "hand.point.up.left"
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: String(localized: "Paddr")
        )
        image?.isTemplate = !model.isEnabled
        statusItem?.button?.image = image
        statusItem?.button?.contentTintColor = model.isEnabled
            ? (model.controllerConnected ? .systemBlue : .systemOrange)
            : nil
        rebuildStatusMenu()
    }

    private func showConfigurationWindow() {
        model.refreshStatus()
        NSApplication.shared.setActivationPolicy(.regular)
        if let window = configurationWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PaddrStyle.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Paddr")
        window.titleVisibility = .visible
        window.toolbarStyle = .unifiedCompact
        window.contentMinSize = PaddrStyle.minimumWindowSize
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ConfigurationView(model: model)
        )
        let autosaveName = "PaddrConfigurationWindow.v4"
        if !window.setFrameUsingName(autosaveName) {
            window.setContentSize(PaddrStyle.defaultWindowSize)
            window.center()
        }
        window.setFrameAutosaveName(autosaveName)

        let controller = NSWindowController(window: window)
        configurationWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === configurationWindowController?.window else {
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
