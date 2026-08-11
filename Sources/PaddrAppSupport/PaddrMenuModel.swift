import Foundation
import Observation
import TrackIsBackCore

@MainActor
@Observable
public final class PaddrMenuModel {
    public var configuration: TrackIsBackConfiguration
    public private(set) var savedConfiguration: TrackIsBackConfiguration
    public var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            beginEnabledTransition()
            statusDidChange?()
        }
    }
    public private(set) var isRunning = false
    public private(set) var controllerDescription: String?
    public private(set) var inputMonitoringStatus: InputMonitoringStatus = .unknown
    public private(set) var accessibilityTrusted = false
    public private(set) var status: MenuStatus = .off
    public private(set) var reportCount = 0
    public private(set) var actionCount = 0
    public private(set) var needsInitialSave = false

    @ObservationIgnored private let dependencies: MenuDependencies
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var lifecycleEpoch: UInt64 = 0
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var permissionRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var terminationCompletion: (@MainActor () -> Void)?
    @ObservationIgnored public var statusDidChange: (@MainActor () -> Void)?

    public var hasUnsavedChanges: Bool { needsInitialSave || configuration != savedConfiguration }
    public var controllerConnected: Bool { controllerDescription != nil }
    public var hasSystemAccess: Bool { inputMonitoringStatus == .granted && accessibilityTrusted }

    public init(dependencies: MenuDependencies = .live) {
        self.dependencies = dependencies
        let loaded: TrackIsBackConfiguration
        let loadFailure: String?
        do {
            loaded = try dependencies.loadConfiguration()
            loadFailure = nil
        } catch {
            loaded = .default
            loadFailure = String(describing: error)
        }
        configuration = loaded
        savedConfiguration = loaded
        if let loadFailure {
            needsInitialSave = true
            status = .failure(.configurationLoad(diagnostic: loadFailure))
        }
        refreshStatus()
    }

    public func refreshStatus() {
        controllerDescription = dependencies.probeController()
        inputMonitoringStatus = dependencies.inputMonitoringStatus()
        accessibilityTrusted = dependencies.accessibilityTrusted(false)
        reconcileCompletedPermissionRequest()
        statusDidChange?()
    }

    public func saveAndApply() {
        let validated: TrackIsBackConfiguration
        do {
            validated = try configuration.validated()
        } catch {
            status = .failure(.configurationInvalid(diagnostic: String(describing: error)))
            statusDidChange?()
            return
        }

        do {
            try dependencies.saveConfiguration(validated)
            configuration = validated
            savedConfiguration = validated
            needsInitialSave = false
            status = .configurationSaved
            if isEnabled { startLifecycle(commitDraft: false) }
        } catch {
            status = .failure(.configurationSave(diagnostic: String(describing: error)))
        }
        statusDidChange?()
    }

    public func restoreDefaults() {
        configuration = .default
        status = .defaultsRestored
    }

    public func requestInputMonitoring() {
        _ = dependencies.requestInputMonitoring()
        inputMonitoringStatus = dependencies.inputMonitoringStatus()
        status = inputMonitoringStatus == .granted ? operationalStatus : .requestingInputMonitoring
        schedulePermissionRefresh()
    }

    public func requestAccessibility() {
        accessibilityTrusted = dependencies.accessibilityTrusted(true)
        status = accessibilityTrusted ? operationalStatus : .requestingAccessibility
        schedulePermissionRefresh()
    }

    public func openInputMonitoringSettings() {
        dependencies.openPrivacySettings("Privacy_ListenEvent")
        status = .inputMonitoringSettings
    }

    public func openAccessibilitySettings() {
        dependencies.openPrivacySettings("Privacy_Accessibility")
        status = .accessibilitySettings
    }

    public func stopForTermination(completion: @escaping @MainActor () -> Void) -> Bool {
        guard isEnabled || sessionID != nil || isRunning || lifecycleTask != nil else { return false }
        terminationCompletion = completion
        status = .releasingOutputs
        lifecycleEpoch &+= 1
        let operation = lifecycleEpoch
        reconnectTask?.cancel()
        reconnectTask = nil
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.dependencies.session.stop()
            guard self.lifecycleEpoch == operation else { return }
            self.finishTerminationIfNeeded()
        }
        return true
    }

    private func beginEnabledTransition() {
        isEnabled ? startLifecycle(commitDraft: true) : stopLifecycle()
    }

    private func startLifecycle(commitDraft: Bool) {
        lifecycleEpoch &+= 1
        let operation = lifecycleEpoch
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            await self?.start(operation: operation, commitDraft: commitDraft)
        }
    }

    private func stopLifecycle() {
        lifecycleEpoch &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        sessionID = nil
        isRunning = false
        status = .off
        lifecycleTask?.cancel()
        lifecycleTask = Task { [dependencies] in await dependencies.session.stop() }
    }

    private func start(operation: UInt64, commitDraft: Bool) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        sessionID = nil
        isRunning = false
        await dependencies.session.stop()
        guard isCurrent(operation), isEnabled else { return }

        if commitDraft, !commitConfigurationForActivation(operation: operation) {
            return
        }

        refreshStatus()
        guard isCurrent(operation), isEnabled else { return }

        guard inputMonitoringStatus == .granted else {
            failEnable(.inputMonitoringRequired, operation: operation)
            return
        }
        guard accessibilityTrusted else {
            failEnable(.accessibilityRequired, operation: operation)
            return
        }
        guard controllerConnected else {
            status = .waitingForController
            scheduleReconnect(operation: operation)
            statusDidChange?()
            return
        }

        let identifier = UUID()
        sessionID = identifier
        reportCount = 0
        actionCount = 0
        status = .connecting
        let stream = await dependencies.session.start(configuration: savedConfiguration, observeOnly: false)
        guard isCurrent(operation), sessionID == identifier else { return }
        for await event in stream {
            guard isCurrent(operation), sessionID == identifier else { return }
            handle(event, sessionID: identifier)
        }
    }

    private func commitConfigurationForActivation(operation: UInt64) -> Bool {
        let validated: TrackIsBackConfiguration
        do {
            validated = try configuration.validated()
        } catch {
            failEnable(
                .configurationInvalid(diagnostic: String(describing: error)),
                operation: operation
            )
            return false
        }

        guard needsInitialSave || validated != savedConfiguration else {
            configuration = validated
            return true
        }

        do {
            try dependencies.saveConfiguration(validated)
            guard isCurrent(operation), isEnabled else { return false }
            configuration = validated
            savedConfiguration = validated
            needsInitialSave = false
            return true
        } catch {
            failEnable(
                .configurationSave(diagnostic: String(describing: error)),
                operation: operation
            )
            return false
        }
    }

    private func failEnable(_ failure: MenuFailure, operation: UInt64) {
        guard lifecycleEpoch == operation else { return }
        isRunning = false
        if isEnabled { isEnabled = false }
        status = .failure(failure)
        statusDidChange?()
    }

    private func scheduleReconnect(operation: UInt64) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            while self.isCurrent(operation), self.isEnabled, !self.isRunning {
                do { try await self.dependencies.sleep(.seconds(1)) }
                catch { return }
                guard self.isCurrent(operation), self.isEnabled, !self.isRunning else { return }
                self.controllerDescription = self.dependencies.probeController()
                if self.controllerConnected {
                    self.reconnectTask = nil
                    self.startLifecycle(commitDraft: false)
                    return
                }
            }
        }
    }

    private func schedulePermissionRefresh() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.dependencies.sleep(.seconds(1)) }
            catch { return }
            self.refreshStatus()
        }
    }

    private var operationalStatus: MenuStatus {
        if isRunning { return .active }
        if isEnabled { return controllerConnected ? .connecting : .waitingForController }
        return .off
    }

    private func reconcileCompletedPermissionRequest() {
        switch status {
        case .requestingInputMonitoring where inputMonitoringStatus == .granted,
             .inputMonitoringSettings where inputMonitoringStatus == .granted:
            status = operationalStatus
        case .requestingAccessibility where accessibilityTrusted,
             .accessibilitySettings where accessibilityTrusted:
            status = operationalStatus
        default:
            break
        }
    }

    private func handle(_ event: TrackpadSessionEvent, sessionID identifier: UUID) {
        guard sessionID == identifier else { return }
        switch event {
        case .connecting:
            status = .connecting
        case let .connected(description):
            controllerDescription = description
            isRunning = true
            status = .active
        case let .progress(summary):
            reportCount = summary.reportCount
            actionCount = summary.actionCount
        case let .stopped(summary):
            update(summary)
            isRunning = false
            sessionID = nil
            if isEnabled, terminationCompletion == nil {
                status = .waitingForController
                scheduleReconnect(operation: lifecycleEpoch)
            } else {
                status = .stopped
            }
            finishTerminationIfNeeded()
        case let .deviceRemoved(summary):
            update(summary)
            controllerDescription = nil
            isRunning = false
            sessionID = nil
            status = .waitingForController
            if isEnabled { scheduleReconnect(operation: lifecycleEpoch) }
            finishTerminationIfNeeded()
        case .deviceUnavailable:
            controllerDescription = nil
            isRunning = false
            sessionID = nil
            status = .waitingForController
            if isEnabled { scheduleReconnect(operation: lifecycleEpoch) }
        case let .failed(message):
            sessionID = nil
            isRunning = false
            let failure = MenuFailure.output(diagnostic: message)
            if isEnabled { isEnabled = false }
            status = .failure(failure)
            finishTerminationIfNeeded()
        }
        statusDidChange?()
    }

    private func update(_ summary: TrackpadRunSummary) {
        reportCount = summary.reportCount
        actionCount = summary.actionCount
    }

    private func finishTerminationIfNeeded() {
        let completion = terminationCompletion
        terminationCompletion = nil
        completion?()
        if completion != nil { statusDidChange?() }
    }

    private func isCurrent(_ operation: UInt64) -> Bool {
        !Task.isCancelled && lifecycleEpoch == operation
    }
}
