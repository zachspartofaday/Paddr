import AppKit
import PaddrAppSupport
import SwiftUI
import TrackIsBackCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = PaddrMenuModel()
    private let onboardingPreferences = OnboardingPreferences()
    private let statusMenu = NSMenu()
    private var statusItem: NSStatusItem?
    private var configurationWindowController: NSWindowController?
    private var guideWindowController: NSWindowController?
    private var guidePresentation = OnboardingWindowPresentation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let shouldShowGuide = OnboardingEligibility.shouldPresent(
            trigger: .automatic,
            hasRecordedDismissal: onboardingPreferences.hasRecordedDismissal
        )

        NSApplication.shared.setActivationPolicy(.accessory)
        installMainMenu()

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
        if shouldShowGuide { showGuideWindow(trigger: .automatic) }
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

    @objc private func showGuideFromHelp() {
        showGuideWindow(trigger: .help)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String else { return }
        let result = model.requestProfileSelection(
            id: ConfigurationProfileID(rawValue: rawID),
            source: .menu
        )
        if result == .blockedByUnsavedChanges { showConfigurationWindow() }
        rebuildStatusMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)
        let applicationMenu = NSMenu(title: String(localized: "Paddr"))
        applicationMenuItem.submenu = applicationMenu

        let aboutItem = NSMenuItem(
            title: String(localized: "About Paddr"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApplication.shared
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: String(localized: "Services"))
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        applicationMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: String(localized: "Hide Paddr"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApplication.shared
        applicationMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApplication.shared
        applicationMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: String(localized: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApplication.shared
        applicationMenu.addItem(showAllItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit Paddr"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        applicationMenu.addItem(quitItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(
            withTitle: String(localized: "Undo"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: String(localized: "Redo"),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: String(localized: "Cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: String(localized: "Copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: String(localized: "Paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: String(localized: "Select All"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: String(localized: "Close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: String(localized: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: String(localized: "Zoom"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: String(localized: "Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: String(localized: "Help"))
        helpMenuItem.submenu = helpMenu
        let guideItem = NSMenuItem(
            title: String(localized: "Paddr Guide…"),
            action: #selector(showGuideFromHelp),
            keyEquivalent: ""
        )
        guideItem.target = self
        helpMenu.addItem(guideItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.servicesMenu = servicesMenu
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.helpMenu = helpMenu
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let outputItem = NSMenuItem(
            title: String(localized: "Trackpad Output"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        outputItem.target = self
        outputItem.isEnabled = model.canToggleOutput
        outputItem.state = model.isEnabled ? .on : .off
        outputItem.image = NSImage(
            systemSymbolName: model.isEnabled ? "wave.3.right.circle.fill" : "pause.circle",
            accessibilityDescription: String(localized: "Trackpad Output")
        )
        statusMenu.addItem(outputItem)
        statusMenu.addItem(.separator())

        let profileHeader = NSMenuItem(title: String(localized: "Profiles"), action: nil, keyEquivalent: "")
        profileHeader.isEnabled = false
        statusMenu.addItem(profileHeader)
        if model.canSelectProfileFromMenu {
            for profile in model.profiles {
                let item = NSMenuItem(
                    title: profile.name,
                    action: #selector(selectProfile(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = profile.id.rawValue
                item.state = profile.id == model.activeProfileID ? .on : .off
                statusMenu.addItem(item)
            }
        } else {
            let item = NSMenuItem(
                title: String(localized: "Open Configuration to switch profiles…"),
                action: #selector(openConfiguration),
                keyEquivalent: ""
            )
            item.target = self
            statusMenu.addItem(item)
        }

        statusMenu.addItem(.separator())
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

        let guideItem = NSMenuItem(
            title: String(localized: "Paddr Guide…"),
            action: #selector(showGuideFromHelp),
            keyEquivalent: ""
        )
        guideItem.target = self
        guideItem.image = NSImage(
            systemSymbolName: "questionmark.circle",
            accessibilityDescription: String(localized: "Paddr Guide")
        )
        statusMenu.addItem(guideItem)

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

    private func showGuideWindow(trigger: OnboardingPresentationTrigger) {
        guard OnboardingEligibility.shouldPresent(
            trigger: trigger,
            hasRecordedDismissal: onboardingPreferences.hasRecordedDismissal
        ) else { return }

        model.refreshStatus()
        NSApplication.shared.setActivationPolicy(.regular)
        switch guidePresentation.requestPresentation() {
        case .focusExisting:
            guard let window = guideWindowController?.window else {
                guidePresentation.didClose()
                showGuideWindow(trigger: trigger)
                return
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        case .create:
            break
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 680, height: 470)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Paddr Guide")
        window.contentMinSize = NSSize(width: 560, height: 430)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingGuideView(
                model: model,
                onSkip: { [weak self] in self?.dismissGuide(as: .skipped) },
                onComplete: { [weak self] in self?.dismissGuide(as: .completed) }
            )
        )
        window.center()

        let controller = NSWindowController(window: window)
        guideWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate()
    }

    private func dismissGuide(as dismissal: OnboardingDismissal) {
        onboardingPreferences.record(dismissal)
        guideWindowController?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === guideWindowController?.window {
            onboardingPreferences.record(.skipped)
            guidePresentation.didClose()
            guideWindowController = nil
            if configurationWindowController?.window?.isVisible != true {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        } else if window === configurationWindowController?.window,
                  guideWindowController?.window?.isVisible != true {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
