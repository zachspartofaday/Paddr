import Foundation
import Observation
import TrackIsBackCore

@MainActor
@Observable
public final class PaddrMenuModel {
    public var configuration: TrackIsBackConfiguration {
        didSet {
            guard !isPublishingConfiguration else { return }
            draftRevision &+= 1
            preservingCurrentOperationalStatusAuthority {
                advanceStatusGeneration()
            }
        }
    }
    public private(set) var savedConfiguration: TrackIsBackConfiguration
    public var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if statusPublicationGeneration == nil { advanceStatusGeneration() }
            beginEnabledTransition(statusGeneration: currentStatusGeneration)
            statusDidChange?()
        }
    }
    public private(set) var isRunning = false
    public private(set) var receiverDescription: String?
    public private(set) var controllerConnected = false
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
    @ObservationIgnored private var draftRevision: UInt64 = 0
    @ObservationIgnored private var statusGeneration: UInt64 = 0
    @ObservationIgnored private var sessionStatusGeneration: UInt64?
    @ObservationIgnored private var statusPublicationGeneration: UInt64?
    @ObservationIgnored private var allowsAuthoritativeStatusPublication = false
    @ObservationIgnored private var isPublishingConfiguration = false
    @ObservationIgnored private var activationCommitPending = false
    @ObservationIgnored private var statusRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var statusRefreshEpoch: UInt64 = 0
    @ObservationIgnored private var receiverStateGeneration: UInt64 = 0
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectStatusGeneration: UInt64?
    @ObservationIgnored private var permissionRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var terminationTask: Task<Void, Never>?
    @ObservationIgnored private var terminationState = TerminationState.idle
    @ObservationIgnored private var terminationCompletions: [@MainActor () -> Void] = []
    @ObservationIgnored public var statusDidChange: (@MainActor () -> Void)?

    public var hasUnsavedChanges: Bool { needsInitialSave || configuration != savedConfiguration }
    public var hasSystemAccess: Bool { accessibilityTrusted }

    public init(dependencies: MenuDependencies = .live) {
        self.dependencies = dependencies
        configuration = .default
        savedConfiguration = .default
        let initialDraftRevision = draftRevision
        let initialStatusGeneration = statusGeneration
        initializationTask = Task { [weak self] in
            await self?.initialize(
                replacingRevision: initialDraftRevision,
                statusGeneration: initialStatusGeneration
            )
        }
    }

    public func refreshStatus() {
        let initiatingStatusGeneration = currentStatusGeneration
        statusRefreshEpoch &+= 1
        let operation = statusRefreshEpoch
        statusRefreshTask?.cancel()
        statusRefreshTask = Task { [weak self] in
            guard let self else { return }
            await initializationTask?.value
            guard !Task.isCancelled,
                  statusRefreshEpoch == operation,
                  terminationState == .idle
            else { return }
            _ = await refreshStatusNow(
                operation: operation,
                statusGeneration: initiatingStatusGeneration
            )
            guard statusRefreshEpoch == operation else { return }
            statusRefreshTask = nil
        }
    }

    public func saveAndApply() {
        guard terminationState == .idle else { return }
        let draft = configuration
        let initiatingDraftRevision = draftRevision
        let validated: TrackIsBackConfiguration
        do {
            validated = try draft.validated()
        } catch {
            publishStatus(.failure(.configurationInvalid(diagnostic: String(describing: error))))
            statusDidChange?()
            return
        }
        preservingCurrentOperationalStatusAuthority {
            advanceStatusGeneration()
        }
        let initiatingStatusGeneration = currentStatusGeneration
        let initiatingLifecycleEpoch = lifecycleEpoch
        let initiatingSessionID = sessionID

        configurationEpoch &+= 1
        let operation = configurationEpoch
        let priorTask = configurationTask
        configurationTask = Task { [weak self] in
            await priorTask?.value
            guard let self else { return }
            await initializationTask?.value
            await saveAndApply(
                validated,
                replacingRevision: initiatingDraftRevision,
                statusGeneration: initiatingStatusGeneration,
                lifecycleEpoch: initiatingLifecycleEpoch,
                sessionID: initiatingSessionID,
                operation: operation
            )
        }
    }

    private func initialize(
        replacingRevision initialDraftRevision: UInt64,
        statusGeneration initialStatusGeneration: UInt64
    ) async {
        var statusGeneration = initialStatusGeneration
        do {
            let loaded = try await dependencies.loadConfiguration()
            if draftRevision == initialDraftRevision { publishConfiguration(loaded) }
            savedConfiguration = loaded
        } catch {
            if draftRevision == initialDraftRevision { publishConfiguration(.default) }
            savedConfiguration = .default
            needsInitialSave = true
            if terminationState == .idle {
                statusGeneration = withStatusPublicationGeneration(statusGeneration) {
                    publishStatus(.failure(.configurationLoad(diagnostic: String(describing: error))))
                }
            }
        }
        isInitialized = true
        _ = await refreshStatusNow(statusGeneration: statusGeneration)
        initializationTask = nil
    }

    private func refreshStatusNow(
        operation: UInt64? = nil,
        statusGeneration initiatingStatusGeneration: UInt64? = nil
    ) async -> UInt64 {
        let statusGeneration = initiatingStatusGeneration ?? self.statusGeneration
        let initiatingReceiverStateGeneration = receiverStateGeneration
        let receiverDescription = await dependencies.probeReceiver()
        guard !Task.isCancelled,
              operation.map({ statusRefreshEpoch == $0 }) ?? true,
              terminationState == .idle
        else { return statusGeneration }
        if receiverStateGeneration == initiatingReceiverStateGeneration {
            self.receiverDescription = receiverDescription
        }
        accessibilityTrusted = dependencies.accessibilityTrusted(false)
        let resultingStatusGeneration = withStatusPublicationGeneration(statusGeneration) {
            reconcileCompletedPermissionRequest()
        }
        statusDidChange?()
        return resultingStatusGeneration
    }

    private func saveAndApply(
        _ validated: TrackIsBackConfiguration,
        replacingRevision initiatingDraftRevision: UInt64,
        statusGeneration initiatingStatusGeneration: UInt64,
        lifecycleEpoch initiatingLifecycleEpoch: UInt64,
        sessionID initiatingSessionID: UUID?,
        operation: UInt64
    ) async {
        do {
            try await dependencies.saveConfiguration(validated)
            guard terminationState == .idle else { return }
            if draftRevision == initiatingDraftRevision { publishConfiguration(validated) }
            savedConfiguration = validated
            needsInitialSave = false
            let resultingStatusGeneration = withStatusPublicationGeneration(
                initiatingStatusGeneration
            ) {
                publishStatus(.configurationSaved)
            }
            if isEnabled,
               configurationEpoch == operation,
               lifecycleEpoch == initiatingLifecycleEpoch {
                startLifecycle(
                    commitDraft: false,
                    statusGeneration: statusGenerationForLifecycleReplacement(
                        completionGeneration: resultingStatusGeneration,
                        replacingSession: initiatingSessionID
                    )
                )
            }
        } catch {
            guard terminationState == .idle else { return }
            withStatusPublicationGeneration(initiatingStatusGeneration) {
                publishStatus(.failure(.configurationSave(diagnostic: String(describing: error))))
            }
        }
        clearConfigurationTask(operation: operation)
        statusDidChange?()
    }

    public func restoreDefaults() {
        guard terminationState == .idle else { return }
        configuration = .default
        publishStatus(.defaultsRestored)
    }

    public func requestAccessibility() {
        guard terminationState == .idle else { return }
        accessibilityTrusted = dependencies.accessibilityTrusted(true)
        if accessibilityTrusted {
            preservingCurrentOperationalStatusAuthority {
                publishStatus(operationalStatus)
            }
        } else {
            publishStatus(.requestingAccessibility)
        }
        schedulePermissionRefresh()
    }

    public func openAccessibilitySettings() {
        guard terminationState == .idle else { return }
        dependencies.openPrivacySettings("Privacy_Accessibility")
        publishStatus(.accessibilitySettings)
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
        publishStatus(.releasingOutputs)
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
        activationCommitPending = false
        statusRefreshTask = nil
        reconnectTask = nil
        reconnectStatusGeneration = nil
        permissionRefreshTask = nil
        sessionID = nil
        controllerConnected = false
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

    private func beginEnabledTransition(statusGeneration: UInt64) {
        guard terminationState == .idle else { return }
        if isEnabled {
            startLifecycle(commitDraft: true, statusGeneration: statusGeneration)
        } else {
            stopLifecycle()
        }
    }

    private func startLifecycle(commitDraft: Bool, statusGeneration: UInt64) {
        guard terminationState == .idle else { return }
        if commitDraft { activationCommitPending = true }
        let shouldCommitDraft = activationCommitPending
        lifecycleEpoch &+= 1
        let operation = lifecycleEpoch
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            guard let self else { return }
            await self.start(
                operation: operation,
                commitDraft: shouldCommitDraft,
                statusGeneration: statusGeneration
            )
            self.clearLifecycleTask(operation: operation)
        }
    }

    private func stopLifecycle() {
        guard terminationState == .idle else { return }
        activationCommitPending = false
        lifecycleEpoch &+= 1
        let operation = lifecycleEpoch
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectStatusGeneration = nil
        sessionID = nil
        controllerConnected = false
        isRunning = false
        publishStatus(.off)
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self, dependencies] in
            await dependencies.session.stop()
            self?.clearLifecycleTask(operation: operation)
        }
    }

    private func start(
        operation: UInt64,
        commitDraft: Bool,
        statusGeneration initiatingStatusGeneration: UInt64
    ) async {
        var statusGeneration = initiatingStatusGeneration
        await initializationTask?.value
        await configurationTask?.value
        guard isCurrent(operation), isEnabled else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectStatusGeneration = nil
        sessionID = nil
        controllerConnected = false
        isRunning = false
        await dependencies.session.stop()
        guard isCurrent(operation), isEnabled else { return }

        if commitDraft {
            guard await commitConfigurationForActivation(
                operation: operation,
                statusGeneration: statusGeneration
            ) else { return }
            guard isCurrent(operation), isEnabled else { return }
            activationCommitPending = false
        }

        statusGeneration = await refreshStatusNow(statusGeneration: statusGeneration)
        guard isCurrent(operation), isEnabled else { return }

        guard accessibilityTrusted else {
            failEnable(
                .accessibilityRequired,
                operation: operation,
                statusGeneration: statusGeneration
            )
            return
        }
        guard receiverDescription != nil else {
            statusGeneration = withStatusPublicationGeneration(statusGeneration) {
                publishStatus(.waitingForController)
            }
            scheduleReconnect(operation: operation, statusGeneration: statusGeneration)
            statusDidChange?()
            return
        }

        let identifier = UUID()
        sessionID = identifier
        reportCount = 0
        actionCount = 0
        statusGeneration = withStatusPublicationGeneration(statusGeneration) {
            publishStatus(.connecting)
        }
        sessionStatusGeneration = statusGeneration
        let stream = await dependencies.session.start(configuration: savedConfiguration, observeOnly: false)
        guard isCurrent(operation), sessionID == identifier else { return }
        for await event in stream {
            guard isCurrent(operation), sessionID == identifier else { return }
            statusGeneration = handle(
                event,
                sessionID: identifier,
                statusGeneration: statusGeneration
            )
        }
    }

    private func commitConfigurationForActivation(
        operation: UInt64,
        statusGeneration: UInt64
    ) async -> Bool {
        while isCurrent(operation), isEnabled {
            let draft = configuration
            let revision = draftRevision
            let validated: TrackIsBackConfiguration
            do {
                validated = try draft.validated()
            } catch {
                failEnable(
                    .configurationInvalid(diagnostic: String(describing: error)),
                    operation: operation,
                    statusGeneration: statusGeneration
                )
                return false
            }

            guard needsInitialSave || validated != savedConfiguration else {
                publishConfiguration(validated)
                return true
            }

            do {
                try await dependencies.saveConfiguration(validated)
                savedConfiguration = validated
                needsInitialSave = false
                guard isCurrent(operation), isEnabled else { return false }
                guard draftRevision == revision else { continue }
                publishConfiguration(validated)
                return true
            } catch {
                failEnable(
                    .configurationSave(diagnostic: String(describing: error)),
                    operation: operation,
                    statusGeneration: statusGeneration
                )
                return false
            }
        }
        return false
    }

    private func failEnable(
        _ failure: MenuFailure,
        operation: UInt64,
        statusGeneration: UInt64
    ) {
        guard lifecycleEpoch == operation else { return }
        withStatusPublicationGeneration(statusGeneration) {
            isRunning = false
            if isEnabled { isEnabled = false }
            publishStatus(.failure(failure))
        }
        statusDidChange?()
    }

    private func scheduleReconnect(operation: UInt64, statusGeneration: UInt64) {
        reconnectTask?.cancel()
        reconnectStatusGeneration = statusGeneration
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            while self.isCurrent(operation), self.isEnabled, !self.isRunning {
                do { try await self.dependencies.sleep(.seconds(1)) }
                catch { return }
                guard self.isCurrent(operation), self.isEnabled, !self.isRunning else { return }
                let receiverDescription = await self.dependencies.probeReceiver()
                guard self.isCurrent(operation), self.isEnabled, !self.isRunning else { return }
                self.receiverStateGeneration &+= 1
                self.receiverDescription = receiverDescription
                if receiverDescription != nil {
                    let reconnectStatusGeneration = self.reconnectStatusGeneration ?? statusGeneration
                    self.reconnectTask = nil
                    self.reconnectStatusGeneration = nil
                    self.startLifecycle(
                        commitDraft: false,
                        statusGeneration: reconnectStatusGeneration
                    )
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
        if isEnabled { return controllerConnected ? .waitingForNeutral : .waitingForController }
        return .off
    }

    private func reconcileCompletedPermissionRequest() {
        switch status {
        case .requestingAccessibility where accessibilityTrusted,
             .accessibilitySettings where accessibilityTrusted:
            let identifier = sessionID
            let priorStatusGeneration = currentStatusGeneration
            publishStatus(operationalStatus)
            if identifier != nil,
               sessionID == identifier,
               currentStatusGeneration != priorStatusGeneration {
                sessionStatusGeneration = currentStatusGeneration
            }
        default:
            break
        }
    }

    private func handle(
        _ event: TrackpadSessionEvent,
        sessionID identifier: UUID,
        statusGeneration: UInt64
    ) -> UInt64 {
        guard sessionID == identifier else { return statusGeneration }
        let sessionStatusGeneration = self.sessionStatusGeneration ?? statusGeneration
        let isSessionEnding: Bool
        switch event {
        case .stopped, .receiverRemoved, .receiverUnavailable, .failed:
            isSessionEnding = true
        case .connecting, .waitingForController, .controllerConnected, .outputArmed,
             .progress, .controllerLost:
            isSessionEnding = false
        }
        var shouldScheduleReconnect = false
        let resultingStatusGeneration = withStatusPublicationGeneration(
            sessionStatusGeneration,
            allowsAuthoritativePublication: isSessionEnding
        ) {
            switch event {
            case .connecting:
                publishStatus(.connecting)
            case let .waitingForController(description):
                receiverStateGeneration &+= 1
                receiverDescription = description
                controllerConnected = false
                isRunning = false
                publishStatus(.waitingForController)
            case .controllerConnected:
                controllerConnected = true
                isRunning = false
                publishStatus(.waitingForNeutral)
            case .outputArmed:
                guard controllerConnected else { break }
                isRunning = true
                publishStatus(.active)
            case let .progress(summary):
                update(summary)
            case let .controllerLost(summary):
                update(summary)
                controllerConnected = false
                isRunning = false
                publishStatus(.waitingForController)
            case let .stopped(summary):
                update(summary)
                controllerConnected = false
                isRunning = false
                sessionID = nil
                if isEnabled, terminationState == .idle {
                    publishStatus(.waitingForController)
                    shouldScheduleReconnect = true
                } else {
                    publishStatus(.stopped)
                }
            case let .receiverRemoved(summary):
                update(summary)
                receiverStateGeneration &+= 1
                receiverDescription = nil
                controllerConnected = false
                isRunning = false
                sessionID = nil
                publishStatus(.waitingForController)
                if isEnabled {
                    shouldScheduleReconnect = true
                }
            case .receiverUnavailable:
                receiverStateGeneration &+= 1
                receiverDescription = nil
                controllerConnected = false
                isRunning = false
                sessionID = nil
                publishStatus(.waitingForController)
                if isEnabled {
                    shouldScheduleReconnect = true
                }
            case let .failed(message):
                sessionID = nil
                controllerConnected = false
                isRunning = false
                let failure = MenuFailure.output(diagnostic: message)
                if isEnabled { isEnabled = false }
                publishStatus(.failure(failure))
            }
        }
        if sessionID == identifier {
            self.sessionStatusGeneration = resultingStatusGeneration
        }
        if shouldScheduleReconnect {
            scheduleReconnect(
                operation: lifecycleEpoch,
                statusGeneration: resultingStatusGeneration
            )
        }
        statusDidChange?()
        return resultingStatusGeneration
    }

    private func update(_ summary: TrackpadRunSummary) {
        reportCount = summary.reportCount
        actionCount = summary.actionCount
    }

    private var currentStatusGeneration: UInt64 {
        statusPublicationGeneration ?? statusGeneration
    }

    private func statusGenerationForLifecycleReplacement(
        completionGeneration: UInt64,
        replacingSession identifier: UUID?
    ) -> UInt64 {
        guard let identifier,
              sessionID == identifier,
              let sessionStatusGeneration,
              sessionStatusGeneration == currentStatusGeneration
        else { return completionGeneration }
        return sessionStatusGeneration
    }

    private func preservingCurrentOperationalStatusAuthority(_ operation: () -> Void) {
        let identifier = sessionID
        let sessionHadStatusAuthority = identifier != nil
            && sessionStatusGeneration == currentStatusGeneration
        let reconnectHadStatusAuthority = reconnectTask != nil
            && reconnectStatusGeneration == currentStatusGeneration
        operation()
        if sessionHadStatusAuthority, sessionID == identifier {
            sessionStatusGeneration = currentStatusGeneration
        }
        if reconnectHadStatusAuthority, reconnectTask != nil {
            reconnectStatusGeneration = currentStatusGeneration
        }
    }

    private func advanceStatusGeneration() {
        if let publicationGeneration = statusPublicationGeneration {
            guard statusGeneration == publicationGeneration else { return }
            statusGeneration &+= 1
            statusPublicationGeneration = statusGeneration
        } else {
            statusGeneration &+= 1
        }
    }

    private func publishStatus(_ newStatus: MenuStatus) {
        if let publicationGeneration = statusPublicationGeneration {
            if statusGeneration != publicationGeneration {
                guard allowsAuthoritativeStatusPublication else { return }
                statusPublicationGeneration = statusGeneration
            }
            statusGeneration &+= 1
            statusPublicationGeneration = statusGeneration
        } else {
            statusGeneration &+= 1
        }
        status = newStatus
    }

    @discardableResult
    private func withStatusPublicationGeneration(
        _ generation: UInt64,
        allowsAuthoritativePublication: Bool = false,
        _ publication: () -> Void
    ) -> UInt64 {
        let priorPublicationGeneration = statusPublicationGeneration
        let priorAllowsAuthoritativePublication = allowsAuthoritativeStatusPublication
        statusPublicationGeneration = generation
        allowsAuthoritativeStatusPublication = allowsAuthoritativePublication
        publication()
        let resultingGeneration = statusPublicationGeneration ?? generation
        statusPublicationGeneration = priorPublicationGeneration
        allowsAuthoritativeStatusPublication = priorAllowsAuthoritativePublication
        return resultingGeneration
    }

    private func publishConfiguration(_ configuration: TrackIsBackConfiguration) {
        isPublishingConfiguration = true
        defer { isPublishingConfiguration = false }
        self.configuration = configuration
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
        activationCommitPending = false
        statusRefreshTask = nil
        lifecycleTask = nil
        reconnectTask = nil
        reconnectStatusGeneration = nil
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
