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
    private(set) var isInitialized = false

    @ObservationIgnored private let dependencies: MenuDependencies
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var lifecycleEpoch: UInt64 = 0
    @ObservationIgnored private var initializationTask: Task<Void, Never>?
    @ObservationIgnored private var configurationTask: Task<Void, Never>?
    @ObservationIgnored private var configurationEpoch: UInt64 = 0
    @ObservationIgnored private var statusRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var permissionRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var terminationTask: Task<Void, Never>?
    @ObservationIgnored private var terminationState = TerminationState.idle
    @ObservationIgnored private var terminationCompletions: [@MainActor () -> Void] = []
    @ObservationIgnored public var statusDidChange: (@MainActor () -> Void)?

    public var hasUnsavedChanges: Bool { needsInitialSave || configuration != savedConfiguration }
    public var controllerConnected: Bool { controllerDescription != nil }
    public var hasSystemAccess: Bool { inputMonitoringStatus == .granted && accessibilityTrusted }

    public init(dependencies: MenuDependencies = .live) {
        self.dependencies = dependencies
        configuration = .default
        savedConfiguration = .default
        initializationTask = Task { [weak self] in
            await self?.initialize()
        }
    }

    public func refreshStatus() {
        statusRefreshTask?.cancel()
        statusRefreshTask = Task { [weak self] in
            guard let self else { return }
            await initializationTask?.value
            guard !Task.isCancelled, terminationState == .idle else { return }
            await refreshStatusNow()
            statusRefreshTask = nil
        }
    }

    public func saveAndApply() {
        guard terminationState == .idle else { return }
        let validated: TrackIsBackConfiguration
        do {
            validated = try configuration.validated()
        } catch {
            status = .failure(.configurationInvalid(diagnostic: String(describing: error)))
            statusDidChange?()
            return
        }

        configurationEpoch &+= 1
        let operation = configurationEpoch
        let priorTask = configurationTask
        configurationTask = Task { [weak self] in
            await priorTask?.value
            guard let self else { return }
            await initializationTask?.value
            await saveAndApply(validated, operation: operation)
        }
    }

    private func initialize() async {
        do {
            let loaded = try await dependencies.loadConfiguration()
            configuration = loaded
            savedConfiguration = loaded
        } catch {
            configuration = .default
            savedConfiguration = .default
            needsInitialSave = true
            status = .failure(.configurationLoad(diagnostic: String(describing: error)))
        }
        isInitialized = true
        await refreshStatusNow()
        initializationTask = nil
    }

    private func refreshStatusNow() async {
        let controllerDescription = await dependencies.probeController()
        guard !Task.isCancelled, terminationState == .idle else { return }
        self.controllerDescription = controllerDescription
        inputMonitoringStatus = dependencies.inputMonitoringStatus()
        accessibilityTrusted = dependencies.accessibilityTrusted(false)
        reconcileCompletedPermissionRequest()
        statusDidChange?()
    }

    private func saveAndApply(
        _ validated: TrackIsBackConfiguration,
        operation: UInt64
    ) async {
        do {
            try await dependencies.saveConfiguration(validated)
            guard terminationState == .idle else { return }
            configuration = validated
            savedConfiguration = validated
            needsInitialSave = false
            status = .configurationSaved
            if isEnabled { startLifecycle(commitDraft: false) }
        } catch {
            guard terminationState == .idle else { return }
            status = .failure(.configurationSave(diagnostic: String(describing: error)))
        }
        clearConfigurationTask(operation: operation)
        statusDidChange?()
    }

    public func restoreDefaults() {
        guard terminationState == .idle else { return }
        configuration = .default
        status = .defaultsRestored
    }

    public func requestInputMonitoring() {
        guard terminationState == .idle else { return }
        _ = dependencies.requestInputMonitoring()
        inputMonitoringStatus = dependencies.inputMonitoringStatus()
        status = inputMonitoringStatus == .granted ? operationalStatus : .requestingInputMonitoring
        schedulePermissionRefresh()
    }

    public func requestAccessibility() {
        guard terminationState == .idle else { return }
        accessibilityTrusted = dependencies.accessibilityTrusted(true)
        status = accessibilityTrusted ? operationalStatus : .requestingAccessibility
        schedulePermissionRefresh()
    }

    public func openInputMonitoringSettings() {
        guard terminationState == .idle else { return }
        dependencies.openPrivacySettings("Privacy_ListenEvent")
        status = .inputMonitoringSettings
    }

    public func openAccessibilitySettings() {
        guard terminationState == .idle else { return }
        dependencies.openPrivacySettings("Privacy_Accessibility")
        status = .accessibilitySettings
    }

    public func stopForTermination(completion: @escaping @MainActor () -> Void) -> Bool {
        switch terminationState {
        case .stopping:
            terminationCompletions.append(completion)
            return true
        case .finished:
            return false
        case .idle:
            break
        }

        guard hasPendingLifecycleWork else {
            permissionRefreshTask?.cancel()
            permissionRefreshTask = nil
            return false
        }

        terminationState = .stopping
        terminationCompletions = [completion]
        status = .releasingOutputs
        lifecycleEpoch &+= 1

        let priorConfigurationTask = configurationTask
        let priorStatusRefreshTask = statusRefreshTask
        let priorLifecycleTask = lifecycleTask
        let priorReconnectTask = reconnectTask
        let priorPermissionTask = permissionRefreshTask
        priorStatusRefreshTask?.cancel()
        priorLifecycleTask?.cancel()
        priorReconnectTask?.cancel()
        priorPermissionTask?.cancel()

        isEnabled = false
        statusRefreshTask = nil
        reconnectTask = nil
        permissionRefreshTask = nil
        sessionID = nil
        isRunning = false

        terminationTask = Task { [self] in
            await dependencies.session.stop()
            await priorConfigurationTask?.value
            await priorStatusRefreshTask?.value
            await priorLifecycleTask?.value
            await priorReconnectTask?.value
            await priorPermissionTask?.value
            completeTermination()
        }
        statusDidChange?()
        return true
    }

    private func beginEnabledTransition() {
        guard terminationState == .idle else { return }
        isEnabled ? startLifecycle(commitDraft: true) : stopLifecycle()
    }

    private func startLifecycle(commitDraft: Bool) {
        guard terminationState == .idle else { return }
        lifecycleEpoch &+= 1
        let operation = lifecycleEpoch
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.start(operation: operation, commitDraft: commitDraft)
            self.clearLifecycleTask(operation: operation)
        }
    }

    private func stopLifecycle() {
        guard terminationState == .idle else { return }
        lifecycleEpoch &+= 1
        let operation = lifecycleEpoch
        reconnectTask?.cancel()
        reconnectTask = nil
        sessionID = nil
        isRunning = false
        status = .off
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self, dependencies] in
            await dependencies.session.stop()
            self?.clearLifecycleTask(operation: operation)
        }
    }

    private func start(operation: UInt64, commitDraft: Bool) async {
        await initializationTask?.value
        await configurationTask?.value
        guard isCurrent(operation), isEnabled else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        sessionID = nil
        isRunning = false
        await dependencies.session.stop()
        guard isCurrent(operation), isEnabled else { return }

        if commitDraft, !(await commitConfigurationForActivation(operation: operation)) {
            return
        }

        await refreshStatusNow()
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

    private func commitConfigurationForActivation(operation: UInt64) async -> Bool {
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
            try await dependencies.saveConfiguration(validated)
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
                let controllerDescription = await self.dependencies.probeController()
                guard self.isCurrent(operation), self.isEnabled, !self.isRunning else { return }
                self.controllerDescription = controllerDescription
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
            if isEnabled, terminationState == .idle {
                status = .waitingForController
                scheduleReconnect(operation: lifecycleEpoch)
            } else {
                status = .stopped
            }
        case let .deviceRemoved(summary):
            update(summary)
            controllerDescription = nil
            isRunning = false
            sessionID = nil
            status = .waitingForController
            if isEnabled { scheduleReconnect(operation: lifecycleEpoch) }
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
        }
        statusDidChange?()
    }

    private func update(_ summary: TrackpadRunSummary) {
        reportCount = summary.reportCount
        actionCount = summary.actionCount
    }

    var hasPendingLifecycleWork: Bool {
        isEnabled || sessionID != nil || isRunning || configurationTask != nil
            || lifecycleTask != nil || reconnectTask != nil
    }

    private func clearConfigurationTask(operation: UInt64) {
        guard configurationEpoch == operation else { return }
        configurationTask = nil
    }

    private func clearLifecycleTask(operation: UInt64) {
        guard lifecycleEpoch == operation, terminationState == .idle else { return }
        lifecycleTask = nil
        statusDidChange?()
    }

    private func completeTermination() {
        guard terminationState == .stopping else { return }
        terminationState = .finished
        initializationTask = nil
        configurationTask = nil
        statusRefreshTask = nil
        lifecycleTask = nil
        reconnectTask = nil
        permissionRefreshTask = nil
        terminationTask = nil
        let completions = terminationCompletions
        terminationCompletions.removeAll()
        for completion in completions { completion() }
        statusDidChange?()
    }

    private func isCurrent(_ operation: UInt64) -> Bool {
        !Task.isCancelled && terminationState == .idle && lifecycleEpoch == operation
    }
}

private enum TerminationState {
    case idle
    case stopping
    case finished
}
