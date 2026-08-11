import AppKit
import Foundation
import Observation
import TrackIsBackCore

@MainActor
@Observable
final class TrackIsBackMenuModel {
    var configuration: TrackIsBackConfiguration
    private(set) var savedConfiguration: TrackIsBackConfiguration
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop(message: "Trackpad output is off.")
            statusDidChange?()
        }
    }
    private(set) var isRunning = false
    private(set) var controllerDescription: String?
    private(set) var inputMonitoringStatus = "unknown"
    private(set) var accessibilityTrusted = false
    private(set) var statusMessage = "Trackpad output is off."
    private(set) var reportCount = 0
    private(set) var actionCount = 0

    @ObservationIgnored private let session = TrackpadSession()
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var terminationCompletion: (@MainActor () -> Void)?
    @ObservationIgnored var statusDidChange: (@MainActor () -> Void)?

    var hasUnsavedChanges: Bool { configuration != savedConfiguration }
    var controllerConnected: Bool { controllerDescription != nil }

    init() {
        let loaded: TrackIsBackConfiguration
        do {
            loaded = try ConfigurationStore.load()
        } catch {
            loaded = .default
        }
        configuration = loaded
        savedConfiguration = loaded
        refreshStatus()
    }

    func refreshStatus() {
        controllerDescription = TritonHIDDevice.probe()?.description
        inputMonitoringStatus = TritonHIDDevice.inputMonitoringStatus()
        accessibilityTrusted = Permissions.accessibilityTrusted(prompt: false)
        statusDidChange?()
    }

    func saveAndApply() {
        do {
            let validated = try configuration.validated()
            try ConfigurationStore.save(validated)
            configuration = validated
            savedConfiguration = validated
            statusMessage = "Configuration saved."
            if isEnabled {
                start()
            }
        } catch {
            statusMessage = String(describing: error)
        }
        statusDidChange?()
    }

    func restoreDefaults() {
        configuration = .default
        statusMessage = "Defaults restored. Save to apply them."
    }

    func requestInputMonitoring() {
        _ = TritonHIDDevice.requestInputMonitoring()
        inputMonitoringStatus = TritonHIDDevice.inputMonitoringStatus()
        statusMessage = inputMonitoringStatus == "granted"
            ? "Input Monitoring is ready."
            : "macOS is requesting Input Monitoring. Complete the prompt, then return to PuckPads."
        schedulePermissionRefresh()
    }

    func requestAccessibility() {
        accessibilityTrusted = Permissions.accessibilityTrusted(prompt: true)
        statusMessage = accessibilityTrusted
            ? "Accessibility is ready."
            : "macOS is requesting Accessibility. Complete the prompt, then return to PuckPads."
        schedulePermissionRefresh()
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
        statusMessage = "Enable PuckPads in Input Monitoring, then return to the app."
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
        statusMessage = "Enable PuckPads in Accessibility, then return to the app."
    }

    func stopForTermination(completion: @escaping @MainActor () -> Void) -> Bool {
        guard sessionID != nil, isRunning else { return false }
        terminationCompletion = completion
        statusMessage = "Releasing mapped keys…"
        session.stop()
        return true
    }

    private func start() {
        stop(message: nil)
        refreshStatus()
        guard TritonHIDDevice.requestInputMonitoring() else {
            failEnable("Input Monitoring is required. Complete the macOS prompt, then turn PuckPads on again.")
            return
        }
        guard Permissions.accessibilityTrusted(prompt: true) else {
            failEnable("Accessibility is required. Complete the macOS prompt, then turn PuckPads on again.")
            return
        }
        do {
            configuration = try configuration.validated()
        } catch {
            failEnable(String(describing: error))
            return
        }

        let identifier = UUID()
        sessionID = identifier
        reportCount = 0
        actionCount = 0
        isRunning = true
        statusMessage = "Connecting…"
        session.start(configuration: configuration) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event, sessionID: identifier)
            }
        }
    }

    private func stop(message: String?) {
        sessionID = nil
        session.stop()
        isRunning = false
        if let message { statusMessage = message }
    }

    private func failEnable(_ message: String) {
        isRunning = false
        isEnabled = false
        statusMessage = message
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func schedulePermissionRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.refreshStatus()
        }
    }

    private func handle(_ event: TrackpadSessionEvent, sessionID identifier: UUID) {
        guard sessionID == identifier else { return }
        switch event {
        case .connecting:
            statusMessage = "Connecting…"
        case let .connected(description):
            controllerDescription = description
            isRunning = true
            statusMessage = "Trackpad output is active."
        case let .progress(summary):
            reportCount = summary.reportCount
            actionCount = summary.actionCount
        case let .stopped(summary):
            reportCount = summary.reportCount
            actionCount = summary.actionCount
            isRunning = false
            statusMessage = "Trackpad output stopped."
            finishTerminationIfNeeded()
        case let .failed(message):
            statusMessage = message
            isRunning = false
            isEnabled = false
            finishTerminationIfNeeded()
        }
        statusDidChange?()
    }

    private func finishTerminationIfNeeded() {
        let completion = terminationCompletion
        terminationCompletion = nil
        completion?()
    }
}
