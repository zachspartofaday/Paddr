import Foundation
import Observation
import TrackIsBackCore

public enum ProfileSelectionSource: Sendable {
    case configurationWindow
    case menu
}

public enum ProfileSelectionRequestResult: Equatable, Sendable {
    case accepted
    case confirmationRequired(ConfigurationProfileID)
    case blockedByUnsavedChanges
    case cancelled
    case operationInProgress
    case unchanged
    case profileNotFound
    case storageUnavailable
}

public enum ProfileSelectionPresentation: Equatable, Sendable {
    case active(ConfigurationProfileID)
    case switching(to: ConfigurationProfileID)

    public var selectedProfileID: ConfigurationProfileID {
        switch self {
        case let .active(id), let .switching(to: id): id
        }
    }
}

@MainActor
@Observable
public final class PaddrMenuModel {
    public var configuration: TrackIsBackConfiguration {
        didSet {
            guard !isPublishingConfiguration, !isRejectingConfigurationEdit else { return }
            guard isInitialized, !replacesActiveConfiguration else {
                isRejectingConfigurationEdit = true
                configuration = oldValue
                isRejectingConfigurationEdit = false
                return
            }
            draftRevision &+= 1
            preservingCurrentOperationalStatusAuthority {
                advanceStatusGeneration()
            }
        }
    }
    public private(set) var savedConfiguration: TrackIsBackConfiguration
    public private(set) var profiles: [ConfigurationProfile] = [.default]
    public private(set) var activeProfileID: ConfigurationProfileID = .default
    public var isEnabled = false {
        didSet {
            guard !isRejectingEnabledChange, isEnabled != oldValue else { return }
            guard isInitialized,
                  isEnabled == false || !profileDocumentSaveInProgress || replacesActiveConfiguration
            else {
                isRejectingEnabledChange = true
                isEnabled = oldValue
                isRejectingEnabledChange = false
                return
            }
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
    public private(set) var isInitialized = false

    @ObservationIgnored private let dependencies: MenuDependencies
    @ObservationIgnored private var profileDocument = ConfigurationProfileDocument.default
    @ObservationIgnored private var storageWriteBlocked = false
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
    @ObservationIgnored private var isRejectingConfigurationEdit = false
    @ObservationIgnored private var isRejectingEnabledChange = false
    private var profileOperationInProgress = false
    private var pendingProfileSelectionID: ConfigurationProfileID?
    @ObservationIgnored private var profileDocumentSaveInProgress = false
    private var replacesActiveConfiguration = false
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
    public var activeProfile: ConfigurationProfile {
        profiles.first { $0.id == activeProfileID } ?? .default
    }
    public var canEditActiveProfile: Bool {
        isInitialized && !replacesActiveConfiguration && activeProfileID != .default
    }
    public var profileSelectionPresentation: ProfileSelectionPresentation {
        if let pendingProfileSelectionID {
            return .switching(to: pendingProfileSelectionID)
        }
        return .active(activeProfileID)
    }
    public var activeProfileControlsAppearEnabled: Bool {
        switch profileSelectionPresentation {
        case .active:
            canEditActiveProfile
        case .switching:
            isInitialized && activeProfileID != .default
        }
    }
    public var canManageProfiles: Bool { isInitialized && !profileOperationInProgress }
    public var canToggleOutput: Bool {
        isInitialized && (!profileDocumentSaveInProgress || replacesActiveConfiguration || isEnabled)
    }
    public var canSaveAndApply: Bool {
        isInitialized
            && !storageWriteBlocked
            && !profileDocumentSaveInProgress
            && !replacesActiveConfiguration
            && (canEditActiveProfile || needsInitialSave)
            && (hasUnsavedChanges || isEnabled)
    }
    public var canSelectProfileFromMenu: Bool {
        isInitialized
            && !hasUnsavedChanges
            && configurationTask == nil
            && !profileDocumentSaveInProgress
    }

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
        guard terminationState == .idle,
              isInitialized,
              !profileDocumentSaveInProgress,
              !replacesActiveConfiguration,
              canEditActiveProfile || needsInitialSave else { return }
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
        if !storageWriteBlocked,
           needsInitialSave,
           activeProfileID == .default,
           validated == .default {
            beginProfileDocumentSave(
                profileDocument,
                replacingActiveConfiguration: isEnabled,
                clearsInitialSave: true
            )
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
        profileOperationInProgress = true
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
            let loaded = try await dependencies.loadProfiles()
            let document = loaded.document
            let configuration = document.activeProfile?.configuration ?? .default
            publishProfileDocument(document)
            if draftRevision == initialDraftRevision { publishConfiguration(configuration) }
            savedConfiguration = configuration
            storageWriteBlocked = false
            if let diagnostic = loaded.diagnostic {
                needsInitialSave = true
                if terminationState == .idle {
                    statusGeneration = withStatusPublicationGeneration(statusGeneration) {
                        publishStatus(.failure(.configurationLoad(diagnostic: diagnostic)))
                    }
                }
            }
        } catch {
            if draftRevision == initialDraftRevision { publishConfiguration(.default) }
            savedConfiguration = .default
            publishProfileDocument(.default)
            storageWriteBlocked = true
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
            guard !storageWriteBlocked else {
                throw TrackIsBackError.configuration(
                    "Profile storage could not be loaded. Preserve or repair the original file, then relaunch Paddr before saving."
                )
            }
            var document = profileDocument
            try document.replaceConfiguration(for: activeProfileID, with: validated)
            try await dependencies.saveProfiles(document)
            guard terminationState == .idle else { return }
            publishProfileDocument(document)
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
        guard terminationState == .idle, isInitialized, canEditActiveProfile else { return }
        configuration = .default
        publishStatus(.defaultsRestored)
    }

    @discardableResult
    public func requestProfileSelection(
        id: ConfigurationProfileID,
        source: ProfileSelectionSource
    ) -> ProfileSelectionRequestResult {
        guard isInitialized else { return .operationInProgress }
        guard profileDocument.profile(id: id) != nil else { return .profileNotFound }
        guard !storageWriteBlocked else { return .storageUnavailable }
        guard configurationTask == nil,
              !profileDocumentSaveInProgress else { return .operationInProgress }
        guard id != activeProfileID else { return .unchanged }
        if hasUnsavedChanges {
            return source == .configurationWindow
                ? .confirmationRequired(id)
                : .blockedByUnsavedChanges
        }
        beginProfileActivation(id: id)
        return .accepted
    }

    @discardableResult
    public func resolveProfileSelection(
        id: ConfigurationProfileID,
        discardChanges: Bool
    ) -> ProfileSelectionRequestResult {
        guard isInitialized else { return .operationInProgress }
        guard discardChanges else { return .cancelled }
        guard profileDocument.profile(id: id) != nil else { return .profileNotFound }
        guard !storageWriteBlocked else { return .storageUnavailable }
        guard configurationTask == nil,
              !profileDocumentSaveInProgress else { return .operationInProgress }
        beginProfileActivation(id: id)
        return .accepted
    }

    @discardableResult
    public func createProfile(named name: String) -> Bool {
        guard canBeginProfileMutation(discardingDraft: true) else { return false }
        do {
            var document = profileDocument
            let profile = try document.createProfile(named: name)
            try document.activateProfile(id: profile.id)
            beginProfileDocumentActivation(document)
            return true
        } catch {
            publishProfileOperationFailure(error)
            return false
        }
    }

    @discardableResult
    public func duplicateActiveProfile() -> Bool {
        guard canBeginProfileMutation(discardingDraft: true) else { return false }
        do {
            var document = profileDocument
            let profile = try document.duplicateProfile(id: activeProfileID)
            try document.activateProfile(id: profile.id)
            beginProfileDocumentActivation(document)
            return true
        } catch {
            publishProfileOperationFailure(error)
            return false
        }
    }

    @discardableResult
    public func renameActiveProfile(to name: String) -> Bool {
        guard canBeginProfileMutation(discardingDraft: false) else { return false }
        do {
            var document = profileDocument
            try document.renameProfile(id: activeProfileID, to: name)
            beginProfileDocumentSave(document)
            return true
        } catch {
            publishProfileOperationFailure(error)
            return false
        }
    }

    @discardableResult
    public func deleteProfile(id: ConfigurationProfileID, confirmed: Bool) -> Bool {
        guard confirmed, canBeginProfileMutation(discardingDraft: false) else { return false }
        guard id != activeProfileID || !hasUnsavedChanges else {
            publishProfileOperationFailure(
                TrackIsBackError.configuration(
                    "Save or discard unsaved changes before deleting the active profile."
                )
            )
            return false
        }
        do {
            var document = profileDocument
            let changesActiveProfile = id == activeProfileID
            try document.deleteProfile(id: id)
            if changesActiveProfile {
                beginProfileDocumentActivation(document)
            } else {
                beginProfileDocumentSave(document)
            }
            return true
        } catch {
            publishProfileOperationFailure(error)
            return false
        }
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

    private func canBeginProfileMutation(discardingDraft: Bool) -> Bool {
        guard isInitialized,
              terminationState == .idle,
              configurationTask == nil,
              !profileDocumentSaveInProgress else { return false }
        guard !storageWriteBlocked else {
            publishProfileOperationFailure(
                TrackIsBackError.configuration(
                    "Profile storage could not be loaded. Preserve or repair the original file, then relaunch Paddr before saving."
                )
            )
            return false
        }
        if discardingDraft, hasUnsavedChanges {
            publishProfileOperationFailure(
                TrackIsBackError.configuration(
                    "Save or discard unsaved changes before changing profiles."
                )
            )
            return false
        }
        return true
    }

    private func beginProfileActivation(id: ConfigurationProfileID) {
        guard canBeginProfileMutation(discardingDraft: false) else { return }
        do {
            var document = profileDocument
            try document.activateProfile(id: id)
            beginProfileDocumentActivation(document)
            if profileOperationInProgress {
                pendingProfileSelectionID = id
            }
        } catch {
            publishProfileOperationFailure(error)
        }
    }

    private func beginProfileDocumentActivation(_ document: ConfigurationProfileDocument) {
        beginProfileDocumentSave(document, replacingActiveConfiguration: true)
    }

    private func beginProfileDocumentSave(_ document: ConfigurationProfileDocument) {
        beginProfileDocumentSave(document, replacingActiveConfiguration: false)
    }

    private func beginProfileDocumentSave(
        _ document: ConfigurationProfileDocument,
        replacingActiveConfiguration: Bool,
        clearsInitialSave: Bool = false
    ) {
        guard isInitialized,
              terminationState == .idle,
              configurationTask == nil else { return }
        guard !storageWriteBlocked else {
            publishProfileOperationFailure(
                TrackIsBackError.configuration(
                    "Profile storage could not be loaded. Preserve or repair the original file, then relaunch Paddr before saving."
                )
            )
            return
        }

        configurationEpoch &+= 1
        let operation = configurationEpoch
        profileOperationInProgress = true
        profileDocumentSaveInProgress = true
        replacesActiveConfiguration = replacingActiveConfiguration
        let shouldRestart = replacingActiveConfiguration && isEnabled
        let operationStatusGeneration: UInt64
        if shouldRestart {
            advanceStatusGeneration()
            operationStatusGeneration = withStatusPublicationGeneration(currentStatusGeneration) {
                publishStatus(.releasingOutputs)
            }
            lifecycleEpoch &+= 1
            lifecycleTask?.cancel()
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectStatusGeneration = nil
            activationCommitPending = false
            sessionID = nil
            sessionStatusGeneration = nil
            controllerConnected = false
            isRunning = false
        } else {
            preservingCurrentOperationalStatusAuthority {
                advanceStatusGeneration()
            }
            operationStatusGeneration = currentStatusGeneration
        }
        statusDidChange?()

        configurationTask = Task { [weak self] in
            guard let self else { return }
            await initializationTask?.value
            guard configurationEpoch == operation, terminationState == .idle else {
                clearConfigurationTask(operation: operation)
                return
            }
            if shouldRestart {
                await dependencies.session.stop()
                guard configurationEpoch == operation,
                      terminationState == .idle else {
                    clearConfigurationTask(operation: operation)
                    return
                }
            }
            do {
                try await dependencies.saveProfiles(document)
                guard configurationEpoch == operation, terminationState == .idle else {
                    clearConfigurationTask(operation: operation)
                    return
                }
                publishProfileDocument(document)
                if replacingActiveConfiguration {
                    let selected = document.activeProfile?.configuration ?? .default
                    publishConfiguration(selected)
                    savedConfiguration = selected
                }
                if replacingActiveConfiguration || clearsInitialSave { needsInitialSave = false }
                if shouldRestart {
                    withStatusPublicationGeneration(operationStatusGeneration) {
                        publishStatus(.configurationSaved)
                    }
                } else {
                    preservingCurrentOperationalStatusAuthority {
                        withStatusPublicationGeneration(operationStatusGeneration) {
                            publishStatus(.configurationSaved)
                        }
                    }
                }
                clearConfigurationTask(operation: operation)
                if shouldRestart, isEnabled {
                    startLifecycle(
                        commitDraft: false,
                        statusGeneration: currentStatusGeneration,
                        sessionAlreadyStopped: true
                    )
                }
            } catch {
                clearConfigurationTask(operation: operation)
                if replacingActiveConfiguration, isEnabled {
                    isEnabled = false
                    withStatusPublicationGeneration(currentStatusGeneration) {
                        publishStatus(
                            .failure(.configurationSave(diagnostic: String(describing: error)))
                        )
                    }
                } else {
                    preservingCurrentOperationalStatusAuthority {
                        withStatusPublicationGeneration(operationStatusGeneration) {
                            publishStatus(
                                .failure(.configurationSave(diagnostic: String(describing: error)))
                            )
                        }
                    }
                }
            }
            statusDidChange?()
        }
    }

    private func publishProfileOperationFailure(_ error: Error) {
        publishStatus(.failure(.configurationInvalid(diagnostic: String(describing: error))))
        statusDidChange?()
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
        guard isInitialized, terminationState == .idle else { return }
        if isEnabled {
            startLifecycle(commitDraft: true, statusGeneration: statusGeneration)
        } else {
            stopLifecycle()
        }
    }

    private func startLifecycle(
        commitDraft: Bool,
        statusGeneration: UInt64,
        sessionAlreadyStopped: Bool = false
    ) {
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
                statusGeneration: statusGeneration,
                sessionAlreadyStopped: sessionAlreadyStopped
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
        statusGeneration initiatingStatusGeneration: UInt64,
        sessionAlreadyStopped: Bool
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
        if !sessionAlreadyStopped {
            await dependencies.session.stop()
            guard isCurrent(operation), isEnabled else { return }
        }

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
        guard await acquireActivationPersistenceBoundary(operation: operation) else { return false }
        defer {
            profileOperationInProgress = false
            profileDocumentSaveInProgress = false
            statusDidChange?()
        }

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
                guard !storageWriteBlocked else {
                    throw TrackIsBackError.configuration(
                        "Profile storage could not be loaded. Preserve or repair the original file, then relaunch Paddr before saving."
                    )
                }
                var document = profileDocument
                try document.replaceConfiguration(for: activeProfileID, with: validated)
                try await dependencies.saveProfiles(document)
                publishProfileDocument(document)
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

    private func acquireActivationPersistenceBoundary(operation: UInt64) async -> Bool {
        while isCurrent(operation), isEnabled {
            guard let pendingConfigurationTask = configurationTask else {
                guard !profileDocumentSaveInProgress else { return false }
                profileOperationInProgress = true
                profileDocumentSaveInProgress = true
                statusDidChange?()
                return true
            }
            await pendingConfigurationTask.value
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
            let priorSessionStatusGeneration = identifier == nil ? nil : sessionStatusGeneration
            let priorReconnectStatusGeneration = reconnectTask == nil
                ? nil
                : reconnectStatusGeneration
            let priorStatusGeneration = currentStatusGeneration
            publishStatus(operationalStatus)
            guard currentStatusGeneration != priorStatusGeneration else { return }
            synchronizeOperationalStatusOwners(
                sessionID: identifier,
                sessionStatusGeneration: priorSessionStatusGeneration,
                reconnectStatusGeneration: priorReconnectStatusGeneration
            )
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
        let priorSessionStatusGeneration = identifier != nil
            && sessionStatusGeneration == currentStatusGeneration
            ? sessionStatusGeneration
            : nil
        let priorReconnectStatusGeneration = reconnectTask != nil
            && reconnectStatusGeneration == currentStatusGeneration
            ? reconnectStatusGeneration
            : nil
        operation()
        synchronizeOperationalStatusOwners(
            sessionID: identifier,
            sessionStatusGeneration: priorSessionStatusGeneration,
            reconnectStatusGeneration: priorReconnectStatusGeneration
        )
    }

    private func synchronizeOperationalStatusOwners(
        sessionID identifier: UUID?,
        sessionStatusGeneration priorSessionStatusGeneration: UInt64?,
        reconnectStatusGeneration priorReconnectStatusGeneration: UInt64?
    ) {
        if let identifier,
           let priorSessionStatusGeneration,
           sessionID == identifier,
           sessionStatusGeneration == priorSessionStatusGeneration {
            sessionStatusGeneration = currentStatusGeneration
        }
        if reconnectTask != nil,
           let priorReconnectStatusGeneration,
           reconnectStatusGeneration == priorReconnectStatusGeneration {
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

    private func publishProfileDocument(_ document: ConfigurationProfileDocument) {
        profileDocument = document
        profiles = document.profiles
        activeProfileID = document.activeProfileID
    }

    var hasPendingLifecycleWork: Bool {
        isEnabled || sessionID != nil || isRunning || configurationTask != nil
            || lifecycleTask != nil || reconnectTask != nil
    }

    private func clearConfigurationTask(operation: UInt64) {
        guard configurationEpoch == operation else { return }
        configurationTask = nil
        profileOperationInProgress = false
        pendingProfileSelectionID = nil
        profileDocumentSaveInProgress = false
        replacesActiveConfiguration = false
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
        profileOperationInProgress = false
        pendingProfileSelectionID = nil
        profileDocumentSaveInProgress = false
        replacesActiveConfiguration = false
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
