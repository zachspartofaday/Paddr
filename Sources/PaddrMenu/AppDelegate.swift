import AppKit
import PaddrAppSupport
import SwiftUI
import PaddrCore

enum PaddrMenuBarPalette {
    static func color(for role: MenuBarTintRole) -> NSColor? {
        switch role {
        case .active:
            active
        case .warning:
            warning
        case .none:
            nil
        }
    }

    private static let active = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 70.0 / 255.0, green: 180.0 / 255.0, blue: 135.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 35.0 / 255.0, green: 125.0 / 255.0, blue: 87.0 / 255.0, alpha: 1)
    }

    private static let warning = NSColor(name: nil) { appearance in
        isDark(appearance)
            ? NSColor(srgbRed: 1, green: 179.0 / 255.0, blue: 64.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 168.0 / 255.0, green: 90.0 / 255.0, blue: 0, alpha: 1)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@MainActor
enum PaddrFamilyWindowChrome {
    static let configurationTitlePointSize: CGFloat = 16

    static let styleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView
    ]

    static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }

    /// Keeps the compact blended titlebar while giving the product name a deliberate,
    /// non-interactive treatment instead of turning it into a toolbar control.
    static func installConfigurationTitle(_ title: String, in window: NSWindow) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: configurationTitlePointSize, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = true
        label.setAccessibilityIdentifier(PaddrAccessibility.identifier("window", "title"))
        label.setAccessibilityLabel(title)
        label.translatesAutoresizingMaskIntoConstraints = false

        let horizontalInset: CGFloat = 10
        let container = NSView(
            frame: NSRect(
                origin: .zero,
                size: NSSize(
                    width: ceil(label.intrinsicContentSize.width) + (2 * horizontalInset),
                    height: 32
                )
            )
        )
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -horizontalInset
            ),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .leading
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
        window.titleVisibility = .hidden
    }

    static func setMinimumUsableLayoutSize(_ size: NSSize, for window: NSWindow) {
        window.contentMinSize = contentSize(forUsableLayoutSize: size, in: window)
    }

    static func setUsableLayoutSize(_ size: NSSize, for window: NSWindow) {
        for _ in 0..<3 {
            window.contentView?.layoutSubtreeIfNeeded()
            guard !window.contentLayoutRect.size.isApproximatelyEqual(to: size) else { return }
            window.setContentSize(contentSize(forUsableLayoutSize: size, in: window))
        }
    }

    /// Restores compact-titlebar geometry while migrating only the former default size.
    /// User-customized frames keep their dimensions except where the new minimum clamps them.
    @discardableResult
    static func restoreAutosavedUsableFrame(
        usingName name: String,
        legacyDefaultSize: NSSize,
        newDefaultSize: NSSize,
        minimumSize: NSSize,
        for window: NSWindow
    ) -> Bool {
        guard window.setFrameUsingName(name) else { return false }
        window.contentView?.layoutSubtreeIfNeeded()
        let restoredSize = window.contentLayoutRect.size
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        let migratedSize = WindowFrameGeometry.migratedUsableSize(
            restoredSize: restoredSize,
            legacyDefaultSize: legacyDefaultSize,
            newDefaultSize: newDefaultSize,
            minimumSize: minimumSize
        )
        if !restoredSize.isApproximatelyEqual(to: migratedSize) {
            setUsableLayoutSize(migratedSize, for: window)
            window.setFrameTopLeftPoint(topLeft)
        }
        return true
    }

    /// Restores a physical frame written under a different toolbar style without silently
    /// changing the usable layout size or the saved top edge.
    @discardableResult
    static func migrateAutosavedFrame(
        usingName name: String,
        from sourceStyle: NSWindow.ToolbarStyle,
        to targetStyle: NSWindow.ToolbarStyle,
        for window: NSWindow
    ) -> Bool {
        window.toolbarStyle = sourceStyle
        guard window.setFrameUsingName(name) else {
            window.toolbarStyle = targetStyle
            return false
        }

        window.contentView?.layoutSubtreeIfNeeded()
        let usableSize = window.contentLayoutRect.size
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.toolbarStyle = targetStyle
        setUsableLayoutSize(usableSize, for: window)
        window.setFrameTopLeftPoint(topLeft)
        return true
    }

    private static func contentSize(
        forUsableLayoutSize size: NSSize,
        in window: NSWindow
    ) -> NSSize {
        window.contentView?.layoutSubtreeIfNeeded()
        return WindowFrameGeometry.contentSize(
            forLayoutSize: size,
            currentContentRect: window.contentRect(forFrameRect: window.frame),
            currentLayoutRect: window.contentLayoutRect
        )
    }
}

private extension NSSize {
    func isApproximatelyEqual(to other: NSSize, tolerance: CGFloat = 0.5) -> Bool {
        abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = PaddrMenuModel()
    private let onboardingPreferences = OnboardingPreferences()
    private let statusMenu = NSMenu()
    private var statusItem: NSStatusItem?
    private var configurationWindowController: NSWindowController?
    private var guideWindowController: NSWindowController?
    private var guidePresentation = OnboardingWindowPresentation()
    private var isResolvingTerminationRequest = false
    private var terminationResolutionTask: Task<Void, Never>?

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
        guard !isResolvingTerminationRequest else { return .terminateLater }
        if model.hasPendingConfigurationPersistence {
            isResolvingTerminationRequest = true
            terminationResolutionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let hasUnsavedChanges = await model.hasUnsavedChangesAfterPendingPersistence()
                terminationResolutionTask = nil
                resolvePreparedTermination(
                    hasUnsavedChanges: hasUnsavedChanges,
                    application: sender
                )
            }
            return .terminateLater
        }
        guard model.hasUnsavedChanges else { return terminationReply(for: sender) }

        isResolvingTerminationRequest = true
        presentUnsavedTerminationAlert(application: sender)
        return .terminateLater
    }

    private func resolvePreparedTermination(
        hasUnsavedChanges: Bool,
        application: NSApplication
    ) {
        guard hasUnsavedChanges else {
            continueDeferredTermination(application)
            return
        }
        presentUnsavedTerminationAlert(application: application)
    }

    private func presentUnsavedTerminationAlert(application: NSApplication) {
        showConfigurationWindow()
        guard let window = configurationWindowController?.window else {
            isResolvingTerminationRequest = false
            application.reply(toApplicationShouldTerminate: false)
            return
        }

        let alert = PaddrUnsavedQuitAlert.make(profileName: model.activeProfile.name)
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                self?.resolveUnsavedTermination(response, application: application)
            }
        }
    }

    private func resolveUnsavedTermination(
        _ response: NSApplication.ModalResponse,
        application: NSApplication
    ) {
        switch PaddrUnsavedQuitAlert.action(for: response) {
        case .saveAndQuit:
            terminationResolutionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let didSave = await model.saveBeforeTermination()
                terminationResolutionTask = nil
                guard didSave else {
                    isResolvingTerminationRequest = false
                    application.reply(toApplicationShouldTerminate: false)
                    return
                }
                continueDeferredTermination(application)
            }
        case .quitWithoutSaving:
            continueDeferredTermination(application)
        case .cancel:
            isResolvingTerminationRequest = false
            application.reply(toApplicationShouldTerminate: false)
        }
    }

    private func terminationReply(
        for application: NSApplication
    ) -> NSApplication.TerminateReply {
        let waitsForOutputRelease = model.stopForTermination { [weak self] shouldTerminate in
            self?.isResolvingTerminationRequest = false
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        if waitsForOutputRelease { isResolvingTerminationRequest = true }
        return waitsForOutputRelease ? .terminateLater : .terminateNow
    }

    private func continueDeferredTermination(_ application: NSApplication) {
        let waitsForOutputRelease = model.stopForTermination { [weak self] shouldTerminate in
            self?.isResolvingTerminationRequest = false
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        if !waitsForOutputRelease {
            isResolvingTerminationRequest = false
            application.reply(toApplicationShouldTerminate: true)
        }
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

    @objc private func openSourceNotices() {
        guard let url = PaddrOpenSourceNotices.url else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
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
        let noticesItem = NSMenuItem(
            title: String(localized: "Open Source Notices…"),
            action: #selector(openSourceNotices),
            keyEquivalent: ""
        )
        noticesItem.target = self
        noticesItem.identifier = NSUserInterfaceItemIdentifier(
            PaddrAccessibility.identifier("menu", "open-source-notices")
        )
        helpMenu.addItem(noticesItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.servicesMenu = servicesMenu
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.helpMenu = helpMenu
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let presentation = MenuBarPresentation(
            isEnabled: model.isEnabled,
            isRunning: model.isRunning,
            isReleasingOutput: model.isReleasingOutput,
            controllerConnected: model.controllerConnected,
            puckConnected: model.receiverDescription != nil,
            profileName: model.activeProfile.name
        )

        addStatusSummary(
            presentation.outputSummary,
            identifier: "output-summary"
        )
        addStatusSummary(
            presentation.controllerSummary,
            identifier: "controller-summary"
        )
        addStatusSummary(
            presentation.transportSummary,
            identifier: "transport-summary"
        )
        addStatusSummary(
            presentation.profileSummary,
            identifier: "profile-summary"
        )
        statusMenu.addItem(.separator())

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
        outputItem.identifier = NSUserInterfaceItemIdentifier(
            PaddrAccessibility.identifier("menu", "output-toggle")
        )
        if let reason = model.readiness.outputDisabledReason {
            outputItem.toolTip = String(localized: reason.message)
        }
        statusMenu.addItem(outputItem)
        statusMenu.addItem(.separator())

        let batteryPresentation = BatteryStatusPresentation(status: model.batteryStatus)
        let batteryLevelItem = NSMenuItem(
            title: batteryPresentation.menuLevel,
            action: nil,
            keyEquivalent: ""
        )
        batteryLevelItem.isEnabled = false
        statusMenu.addItem(batteryLevelItem)
        let batteryChargeStateItem = NSMenuItem(
            title: batteryPresentation.menuChargeState,
            action: nil,
            keyEquivalent: ""
        )
        batteryChargeStateItem.isEnabled = false
        statusMenu.addItem(batteryChargeStateItem)
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

        let noticesItem = NSMenuItem(
            title: String(localized: "Open Source Notices…"),
            action: #selector(openSourceNotices),
            keyEquivalent: ""
        )
        noticesItem.target = self
        noticesItem.image = NSImage(
            systemSymbolName: "doc.text",
            accessibilityDescription: String(localized: "Open Source Notices")
        )
        noticesItem.identifier = NSUserInterfaceItemIdentifier(
            PaddrAccessibility.identifier("menu", "open-source-notices")
        )
        statusMenu.addItem(noticesItem)

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
        let presentation = MenuBarPresentation(
            isEnabled: model.isEnabled,
            isRunning: model.isRunning,
            isReleasingOutput: model.isReleasingOutput,
            controllerConnected: model.controllerConnected,
            puckConnected: model.receiverDescription != nil,
            profileName: model.activeProfile.name
        )
        let image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.accessibilityLabel
        )
        image?.isTemplate = presentation.usesTemplateImage
        statusItem?.button?.image = image
        statusItem?.button?.contentTintColor = PaddrMenuBarPalette.color(
            for: presentation.tintRole
        )
        statusItem?.button?.toolTip = presentation.accessibilityLabel
        statusItem?.button?.setAccessibilityLabel(presentation.accessibilityLabel)
        statusItem?.button?.setAccessibilityIdentifier(
            PaddrAccessibility.identifier("status-item")
        )
        rebuildStatusMenu()
    }

    private func addStatusSummary(_ title: String, identifier: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.identifier = NSUserInterfaceItemIdentifier(
            PaddrAccessibility.identifier("menu", identifier)
        )
        statusMenu.addItem(item)
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
            contentRect: NSRect(origin: .zero, size: PaddrStyle.Metrics.defaultWindowSize),
            styleMask: PaddrFamilyWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Paddr")
        window.appearance = NSAppearance(named: .darkAqua)
        window.toolbarStyle = .unifiedCompact
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ConfigurationView(model: model)
        )
        PaddrFamilyWindowChrome.apply(to: window)
        PaddrFamilyWindowChrome.installConfigurationTitle(window.title, in: window)
        let autosaveName = "PaddrConfigurationWindow.v8"
        let previousAutosaveName = "PaddrConfigurationWindow.v7"
        let expandedAutosaveName = "PaddrConfigurationWindow.v6"
        let compactAutosaveName = "PaddrConfigurationWindow.v5"
        let legacyAutosaveName = "PaddrConfigurationWindow.v4"
        if !window.setFrameUsingName(autosaveName) {
            if PaddrFamilyWindowChrome.restoreAutosavedUsableFrame(
                usingName: previousAutosaveName,
                legacyDefaultSize: NSSize(width: 1_280, height: 700),
                newDefaultSize: PaddrStyle.Metrics.defaultWindowSize,
                minimumSize: PaddrStyle.Metrics.minimumWindowSize,
                for: window
            ) {
                // The former default grows to reveal both cards; custom frames are preserved.
            } else if PaddrFamilyWindowChrome.migrateAutosavedFrame(
                usingName: expandedAutosaveName,
                from: .unified,
                to: .unifiedCompact,
                for: window
            ) {
                // Migrated under the short-lived regular unified titlebar geometry.
            } else if window.setFrameUsingName(compactAutosaveName) {
                // This frame already uses compact titlebar geometry.
            } else if window.setFrameUsingName(legacyAutosaveName) {
                let legacyUsableSize = window.contentRect(forFrameRect: window.frame).size
                PaddrFamilyWindowChrome.setUsableLayoutSize(legacyUsableSize, for: window)
            } else {
                PaddrFamilyWindowChrome.setUsableLayoutSize(
                    PaddrStyle.Metrics.defaultWindowSize,
                    for: window
                )
                window.center()
            }
        }
        PaddrFamilyWindowChrome.setMinimumUsableLayoutSize(
            PaddrStyle.Metrics.minimumWindowSize,
            for: window
        )
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
            contentRect: NSRect(origin: .zero, size: PaddrStyle.Metrics.guideWindowSize),
            styleMask: PaddrFamilyWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Paddr Guide")
        window.appearance = NSAppearance(named: .darkAqua)
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
        PaddrFamilyWindowChrome.apply(to: window)
        PaddrFamilyWindowChrome.setUsableLayoutSize(
            PaddrStyle.Metrics.guideWindowSize,
            for: window
        )
        PaddrFamilyWindowChrome.setMinimumUsableLayoutSize(
            PaddrStyle.Metrics.minimumGuideWindowSize,
            for: window
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
        } else if window !== configurationWindowController?.window {
            return
        }
        updateActivationPolicy(afterClosing: window)
    }

    private func updateActivationPolicy(afterClosing closingWindow: NSWindow) {
        let companionWindows = [
            configurationWindowController?.window,
            guideWindowController?.window
        ]
        .compactMap { $0 }
        .filter { $0 !== closingWindow }
        let requiresRegularActivation = companionWindows.contains { window in
            CompanionWindowState(
                isVisible: window.isVisible,
                isMiniaturized: window.isMiniaturized
            ).requiresRegularActivation
        }
        NSApplication.shared.setActivationPolicy(
            requiresRegularActivation ? .regular : .accessory
        )
    }
}
