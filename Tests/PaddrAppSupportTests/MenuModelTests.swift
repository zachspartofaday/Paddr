import Foundation
import Synchronization
import XCTest
@testable import PaddrAppSupport
import TrackIsBackCore

@MainActor
final class MenuModelTests: XCTestCase {
    func testInitializationLoadsConfigurationOffMainActorBeforePublishingSnapshot() async {
        let state = readyState(receiver: nil)
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        XCTAssertFalse(model.isInitialized)
        XCTAssertEqual(model.configuration, .default)
        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration.left.sensitivity, 4)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 4)
        XCTAssertEqual(state.loadRanOnMainThread, false)
    }

    func testCreateBeforeInitializationCannotReplaceStoredProfiles() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        XCTAssertFalse(model.createProfile(named: "New"))
        XCTAssertEqual(state.saveCallCount, 0)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }

        XCTAssertEqual(model.profiles, document.profiles)
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration, first.configuration)
        XCTAssertEqual(model.profiles.first(where: { $0.id == second.id }), second)
        XCTAssertEqual(state.saveCallCount, 0)
        XCTAssertNil(state.savedProfileDocument)
    }

    func testDuplicateBeforeInitializationCannotReplaceStoredProfiles() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        XCTAssertFalse(model.duplicateActiveProfile())
        XCTAssertEqual(state.saveCallCount, 0)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }

        XCTAssertEqual(model.profiles, document.profiles)
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration, first.configuration)
        XCTAssertEqual(model.profiles.first(where: { $0.id == second.id }), second)
        XCTAssertEqual(state.saveCallCount, 0)
        XCTAssertNil(state.savedProfileDocument)
    }

    func testProfileSelectionAndCapabilitiesRemainUnavailableUntilInitialization() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        XCTAssertFalse(model.isInitialized)
        XCTAssertFalse(model.canEditActiveProfile)
        XCTAssertFalse(model.canSaveAndApply)
        XCTAssertFalse(model.canSelectProfileFromMenu)
        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .operationInProgress
        )
        XCTAssertEqual(
            model.resolveProfileSelection(id: second.id, discardChanges: true),
            .operationInProgress
        )
        XCTAssertFalse(model.renameActiveProfile(to: "Renamed"))
        XCTAssertFalse(model.deleteProfile(id: first.id, confirmed: true))
        XCTAssertEqual(state.saveCallCount, 0)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.profiles, document.profiles)
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertTrue(model.canSelectProfileFromMenu)
        XCTAssertEqual(state.saveCallCount, 0)
    }

    func testSaveAndApplyBeforeInitializationCannotReplaceLoadFailure() async {
        let state = readyState(receiver: nil)
        state.loadFailure = "Unreadable configuration"
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.configuration.left.sensitivity = 21
        model.saveAndApply()

        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(state.saveCallCount, 0)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(model.savedConfiguration, .default)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.needsInitialSave)
        XCTAssertEqual(state.saveCallCount, 0)
        guard case let .failure(.configurationLoad(diagnostic)) = model.status else {
            return XCTFail("Expected the load failure")
        }
        XCTAssertEqual(diagnostic, "Unreadable configuration")
    }

    func testEnableBeforeInitializationDoesNotStartOrPersist() async {
        let state = readyState(receiver: "Fake")
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))

        model.isEnabled = true

        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(state.saveCallCount, 0)
        let preInitializationStartCount = await session.startCount
        XCTAssertEqual(preInitializationStartCount, 0)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration.left.sensitivity, 4)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 4)
        XCTAssertEqual(state.saveCallCount, 0)
        await waitUntil(model: model) { await session.startCount == 1 }
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(state.saveCallCount, 0)
    }

    func testInitializationFailurePreservesNewerPermissionGuidanceAndReconcilesIt() async {
        let state = ModelDependencyState()
        state.loadFailure = "Unreadable configuration"
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let sleeper = ManualSleeper()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, sleeper: sleeper))

        model.requestAccessibility()
        model.openAccessibilitySettings()
        XCTAssertEqual(model.status, .accessibilitySettings)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.savedConfiguration, .default)
        XCTAssertTrue(model.needsInitialSave)
        guard model.status == .accessibilitySettings else {
            return XCTFail("Expected newer permission guidance to survive load failure")
        }

        state.accessibilityGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }
    }

    func testEditAndEnableAfterInitializationPersistsAndActivatesNewerDraft() async {
        let state = readyState(receiver: "Fake")
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.configuration.left.sensitivity = 7
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 2 }

        let startedSensitivity = await session.startedConfigurations.last?.left.sensitivity
        XCTAssertEqual(model.configuration.left.sensitivity, 7)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 7)
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 7)
        XCTAssertEqual(startedSensitivity, 7)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testDraftAndDefaultsBeforeInitializationCannotReplaceLoadedConfiguration() async {
        let state = readyState(receiver: nil)
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.configuration.left.sensitivity = 7
        model.restoreDefaults()

        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(model.status, .off)

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration.left.sensitivity, 4)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 4)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(state.saveCallCount, 0)
    }

    func testMissingAccessibilityTurnsOutputBackOffWithFailure() async {
        let state = ModelDependencyState()
        state.accessibilityGranted = false
        state.receiver = "Fake"
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        XCTAssertFalse(model.isRunning)
        guard case .failure = model.status else { return XCTFail("Expected a permission failure") }
    }

    func testAccessibilityGrantAloneStartsSession() async {
        let state = ModelDependencyState()
        state.accessibilityGranted = true
        state.receiver = "Fake"
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
        XCTAssertTrue(model.hasSystemAccess)

        model.isEnabled = true
        for _ in 0..<1_000 {
            if model.isRunning || !model.isEnabled { break }
            await Task.yield()
        }

        let startCount = await session.startCount
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(startCount, 2)
        XCTAssertTrue(model.isRunning)
        XCTAssertFalse(model.canSaveAndApply)
    }

    func testDisconnectedEnableStaysOnAndWaits() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.controllerConnected)
    }

    func testReceiverProbeAloneNeverClaimsControllerConnectedOrOutputActive() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        XCTAssertEqual(model.receiverDescription, "Fake receiver")
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        model.isEnabled = true

        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertNotEqual(model.status, .active)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testControllerPresenceAndNeutralArmingAreDistinctStatusTransitions() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true

        await session.send(.waitingForController("Fake receiver"))
        await waitUntil(model: model) { model.status == .waitingForController }
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertEqual(model.status, .active)
    }

    func testProgressPressurePreservesReconnectedActiveStateAndLatestCounters() async {
        let state = readyState(receiver: nil)
        let session = ProgressPressureSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }

        state.receiver = "Fake receiver"
        model.isEnabled = true
        await waitUntil(model: model) {
            model.isRunning && model.reportCount == 80 && model.actionCount == 8
        }

        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .active)
        XCTAssertEqual(model.reportCount, 80)
        XCTAssertEqual(model.actionCount, 8)

        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testControllerLossKeepsReceiverStreamAndWaitsForFreshEvidence() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.isRunning }

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }

        XCTAssertEqual(model.receiverDescription, "Fake receiver")
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)
        var startCount = await session.startCount
        XCTAssertEqual(startCount, 1)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testDraftEditKeepsCurrentSessionControllerTransitionsAuthoritative() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.status == .active }

        model.configuration.left.sensitivity = 3
        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }

        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertEqual(model.status, .active)
    }

    func testSaveAndApplyKeepsCurrentSessionStatusAuthoritativeWhileSaveIsPending() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.status == .active }

        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .active)
        XCTAssertEqual(state.saveCallCount, 1)

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { await session.startCount == 2 }
        await session.send(.waitingForController("Fake receiver"))
        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertEqual(model.status, .active)
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testSupersededSaveCompletionDoesNotSupersedeCurrentSessionLifecycle() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.status == .active }

        model.configuration.left.sensitivity = 3
        let firstSaveGate = DispatchSemaphore(value: 0)
        state.saveGate = firstSaveGate
        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }

        model.configuration.left.sensitivity = 5
        model.saveAndApply()
        let secondSaveGate = DispatchSemaphore(value: 0)
        state.saveGate = secondSaveGate
        firstSaveGate.signal()
        await waitUntil { state.saveCallCount == 2 && state.saveCompletionCount == 1 }

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        for _ in 0..<1_000 {
            if !model.controllerConnected { break }
            await Task.yield()
        }
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)
        let startCountBeforeLatestCompletion = await session.startCount
        XCTAssertEqual(startCountBeforeLatestCompletion, 1)

        state.saveGate = nil
        secondSaveGate.signal()
        await waitUntil(model: model) {
            await session.startCount == 2 && state.saveCompletionCount == 2
        }
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testDelayedSaveFailureDoesNotRestartOrHideCurrentSessionState() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.status == .active }

        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { model.status == .waitingForController }
        state.saveFailure = "disk full"
        state.saveGate = nil
        let statusChangeCount = state.statusChangeCount
        model.statusDidChange = { state.statusChangeCount += 1 }
        saveGate.signal()
        await waitUntil { state.statusChangeCount > statusChangeCount }
        model.statusDidChange = nil

        let startCount = await session.startCount
        XCTAssertEqual(state.saveCompletionCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .waitingForController)
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testReconnectStartsSessionAndBecomesActive() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { model.isRunning }

        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.controllerConnected)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testDisconnectedDraftEditKeepsReconnectLifecycleStatusAuthoritative() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.configuration.left.sensitivity = 3
        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .connecting)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .active)
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testReconnectDoesNotAdoptNewerUnrelatedStatusAuthority() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.configuration.left.sensitivity = 21
        model.saveAndApply()
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected the newer validation failure")
        }

        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }
        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }

        XCTAssertFalse(model.isRunning)
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected reconnect to preserve the newer validation failure")
        }
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testPermissionRecoveryRestoresReconnectStatusAuthority() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        state.accessibilityGranted = false
        model.openAccessibilitySettings()
        XCTAssertEqual(model.status, .accessibilitySettings)

        state.accessibilityGranted = true
        model.refreshStatus()
        await waitUntil(model: model) { model.status == .waitingForController }
        XCTAssertTrue(model.hasSystemAccess)
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .connecting)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .active)
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testUntrustedAndSupersededPermissionRefreshCannotGrantReconnectAuthority() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        state.accessibilityGranted = false
        model.openAccessibilitySettings()
        model.refreshStatus()
        await waitUntil(model: model) { !model.hasSystemAccess }
        XCTAssertEqual(model.status, .accessibilitySettings)

        let probeCount = state.probeCallCount
        let probeGate = DispatchSemaphore(value: 0)
        state.probeGate = probeGate
        model.refreshStatus()
        await waitUntil { state.probeCallCount > probeCount }
        model.openAccessibilitySettings()
        state.accessibilityGranted = true

        let statusChangeCount = state.statusChangeCount
        model.statusDidChange = { state.statusChangeCount += 1 }
        state.probeGate = nil
        probeGate.signal()
        await waitUntil { state.statusChangeCount > statusChangeCount }
        model.statusDidChange = nil
        XCTAssertTrue(model.hasSystemAccess)
        XCTAssertEqual(model.status, .accessibilitySettings)

        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }
        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }

        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .accessibilitySettings)
        model.isEnabled = false
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }
    }

    func testDeviceRemovalKeepsToggleOnAndReturnsToWaiting() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [
            .controllerConnected,
            .outputArmed,
            .receiverRemoved(.init(reportCount: 4, actionCount: 2))
        ])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController && model.reportCount == 4 }

        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.receiverDescription)
    }

    func testDeviceRemovalPublishesAfterNoOpStatusRefresh() async {
        let state = readyState(receiver: "Fake")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake puck")
        await waitUntil(model: model) { model.status == .active }
        let probeCount = state.probeCallCount

        model.refreshStatus()
        await waitUntil { state.probeCallCount > probeCount }
        await session.send(.receiverRemoved(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.isRunning && model.receiverDescription == nil }

        XCTAssertEqual(model.status, .waitingForController)
        XCTAssertTrue(model.isEnabled)
    }

    func testRefreshStatusDoesNotOverwriteConnectedSessionDescription() async {
        let state = readyState(receiver: "Probe puck")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Initial session puck")
        await waitUntil(model: model) { model.status == .active }

        let probeCount = state.probeCallCount
        let probeGate = DispatchSemaphore(value: 0)
        state.probeGate = probeGate
        state.receiver = nil
        model.refreshStatus()
        await waitUntil { state.probeCallCount > probeCount }
        await session.connect(receiver: "Session puck")
        await waitUntil(model: model) { model.receiverDescription == "Session puck" }

        let statusChangeCount = state.statusChangeCount
        model.statusDidChange = { state.statusChangeCount += 1 }
        probeGate.signal()
        await waitUntil { state.statusChangeCount > statusChangeCount }
        model.statusDidChange = nil
        state.probeGate = nil

        XCTAssertEqual(model.receiverDescription, "Session puck")
        XCTAssertTrue(model.controllerConnected)
    }

    func testDelayedReceiverProbeCannotRestoreControllerLivenessAfterLoss() async {
        let state = readyState(receiver: "Probe receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Session receiver")
        await waitUntil(model: model) { model.isRunning }

        let probeCount = state.probeCallCount
        let probeGate = DispatchSemaphore(value: 0)
        state.probeGate = probeGate
        state.receiver = "Delayed receiver"
        model.refreshStatus()
        await waitUntil { state.probeCallCount > probeCount }
        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }

        let statusChangeCount = state.statusChangeCount
        model.statusDidChange = { state.statusChangeCount += 1 }
        probeGate.signal()
        await waitUntil { state.statusChangeCount > statusChangeCount }
        model.statusDidChange = nil
        state.probeGate = nil

        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)
    }

    func testRefreshStatusDoesNotRestoreRemovedControllerDescription() async {
        let state = readyState(receiver: "Probe puck")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Session puck")
        await waitUntil(model: model) { model.status == .active }

        let probeCount = state.probeCallCount
        let probeGate = DispatchSemaphore(value: 0)
        state.probeGate = probeGate
        state.receiver = "Probe puck"
        model.refreshStatus()
        await waitUntil { state.probeCallCount > probeCount }
        await session.send(.receiverRemoved(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.isRunning && model.receiverDescription == nil }

        let statusChangeCount = state.statusChangeCount
        model.statusDidChange = { state.statusChangeCount += 1 }
        probeGate.signal()
        await waitUntil { state.statusChangeCount > statusChangeCount }
        model.statusDidChange = nil
        state.probeGate = nil

        XCTAssertNil(model.receiverDescription)
        XCTAssertFalse(model.controllerConnected)
    }

    func testSessionFailurePublishesAfterPermissionGuidance() async {
        let state = readyState(receiver: "Fake")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake puck")
        await waitUntil(model: model) { model.status == .active }

        state.accessibilityGranted = false
        model.openAccessibilitySettings()
        XCTAssertEqual(model.status, .accessibilitySettings)
        await session.send(.failed("Puck disconnected"))
        await waitUntil(model: model) { !model.isEnabled && !model.isRunning }

        guard case let .failure(.output(diagnostic)) = model.status else {
            return XCTFail("Expected the terminal session failure")
        }
        XCTAssertEqual(diagnostic, "Puck disconnected")
    }

    func testReconnectPublishesTransitionsAfterStatusRefreshes() async {
        let state = readyState(receiver: "Fake")
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake puck")
        await waitUntil(model: model) { model.status == .active }
        let probeCount = state.probeCallCount

        model.refreshStatus()
        await waitUntil { state.probeCallCount > probeCount }
        await session.send(.receiverRemoved(.init(reportCount: 0, actionCount: 0)))
        await waitUntil(model: model) { !model.isRunning && model.receiverDescription == nil }
        XCTAssertEqual(model.status, .waitingForController)
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 2 }

        XCTAssertEqual(model.status, .connecting)
        await session.connect(receiver: "Reconnected puck")
        await waitUntil(model: model) { model.status == .active }
        XCTAssertEqual(model.receiverDescription, "Reconnected puck")
    }

    func testSaveAndApplyPersistsValidatedConfiguration() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3.4
        model.configuration.left.mouseAcceleration = 0.25
        model.configuration.right.mouseAcceleration = 0.75

        model.saveAndApply()
        await waitUntil(model: model) { model.status == .configurationSaved }

        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3.4)
        XCTAssertEqual(state.savedConfiguration?.left.mouseAcceleration, 0.25)
        XCTAssertEqual(state.savedConfiguration?.right.mouseAcceleration, 0.75)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .configurationSaved)
    }

    func testSaveCompletionPreservesNewerDraft() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }
        model.configuration.left.sensitivity = 5
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.savedConfiguration.left.sensitivity == 3 }

        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 3)
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testOlderSaveCompletionPreservesNewerValidationFailureStatus() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }
        model.configuration.left.sensitivity = 21
        model.saveAndApply()
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected the newer validation failure")
        }

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.savedConfiguration.left.sensitivity == 3 }

        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 3)
        XCTAssertEqual(model.configuration.left.sensitivity, 21)
        XCTAssertTrue(model.hasUnsavedChanges)
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected the newer validation failure to remain published")
        }
    }

    func testSaveCompletionPreservesNewerPermissionGuidanceAndPersistedSnapshot() async {
        let state = ModelDependencyState()
        state.accessibilityGranted = true
        let sleeper = ManualSleeper()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, sleeper: sleeper))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }
        model.requestAccessibility()
        model.openAccessibilitySettings()
        XCTAssertEqual(model.status, .accessibilitySettings)

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.savedConfiguration.left.sensitivity == 3 }

        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 3)
        XCTAssertFalse(model.hasUnsavedChanges)
        guard model.status == .accessibilitySettings else {
            return XCTFail("Expected newer permission guidance to survive save completion")
        }

        state.accessibilityGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }
    }

    func testAlreadyGrantedAccessibilityRequestReturnsToOperationalStatus() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.requestAccessibility()
        XCTAssertEqual(model.status, .off)
    }

    func testAlreadyGrantedAccessibilityRequestKeepsCurrentSessionStatusAuthoritative() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.status == .active }

        model.requestAccessibility()
        XCTAssertEqual(model.status, .active)

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .active)
    }

    func testAccessibilityRequestInvokesPromptDependency() async {
        let state = ModelDependencyState()
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.requestAccessibility()

        XCTAssertEqual(state.accessibilityPromptValues.last, true)
        XCTAssertEqual(state.openedPrivacySettingsAnchors, [])
        XCTAssertEqual(model.status, .requestingAccessibility)
    }

    func testAccessibilitySettingsFallbackOpensSettingsWhenRequestDoesNotGrant() async {
        let state = ModelDependencyState()
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.requestAccessibility()
        model.openAccessibilitySettings()

        XCTAssertEqual(state.accessibilityPromptValues.last, true)
        XCTAssertEqual(state.openedPrivacySettingsAnchors, ["Privacy_Accessibility"])
        XCTAssertEqual(model.status, .accessibilitySettings)
    }

    func testDelayedPermissionRefreshClearsRequestingAccessibilityStatus() async {
        let state = ModelDependencyState()
        let sleeper = ManualSleeper()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, sleeper: sleeper))
        await waitUntil(model: model) { model.isInitialized }

        model.requestAccessibility()
        XCTAssertEqual(model.status, .requestingAccessibility)
        state.accessibilityGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }
    }

    func testSessionEventPreservesNewerPermissionGuidanceButRecordsRuntimeState() async {
        let state = readyState(receiver: "Fake")
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        model.isEnabled = true
        state.accessibilityGranted = false
        model.requestAccessibility()
        model.openAccessibilitySettings()
        XCTAssertEqual(model.status, .accessibilitySettings)

        await session.connect(receiver: "Fake puck")
        await waitUntil(model: model) { model.isRunning }

        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.receiverDescription, "Fake puck")
        guard model.status == .accessibilitySettings else {
            return XCTFail("Expected permission guidance to survive the deferred session event")
        }

        state.accessibilityGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .active }
    }

    func testPermissionReconciliationRestoresCurrentSessionStatusAuthority() async {
        let state = readyState(receiver: "Fake")
        let sleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        model.isEnabled = true
        await session.connect(receiver: "Fake puck")
        await waitUntil(model: model) { model.status == .active }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)

        state.accessibilityGranted = false
        model.requestAccessibility()
        model.openAccessibilitySettings()
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .accessibilitySettings)

        state.accessibilityGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .active }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertTrue(model.isRunning)

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForController)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .waitingForNeutral)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertEqual(model.status, .active)
    }

    func testEnableSavesDraftBeforeStarting() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.configuration.left.sensitivity = 7

        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 2 }

        let startedSensitivity = await session.startedConfigurations.last?.left.sensitivity
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 7)
        XCTAssertEqual(startedSensitivity, 7)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEnableSavePersistsNewerDraftBeforeStarting() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.isEnabled = true
        await waitUntil { state.saveCallCount == 1 }
        model.configuration.left.sensitivity = 5
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { await session.startCount == 2 }

        let startedSensitivity = await session.startedConfigurations.last?.left.sensitivity
        XCTAssertEqual(state.saveCallCount, 2)
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 5)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 5)
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertEqual(startedSensitivity, 5)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEnableDrainsConfigurationTaskHandoffBeforeActivationCommit() async throws {
        let state = readyState(receiver: "Fake puck")
        let (document, first, _) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let recorder = OperationRecorder()
        state.operationRecorder = recorder
        let session = RecordingSession(recorder: recorder)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil { recorder.values.contains("start") }

        model.configuration.left.sensitivity = 3
        let firstSaveGate = DispatchSemaphore(value: 0)
        state.saveGate = firstSaveGate
        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }

        model.configuration.left.sensitivity = 5
        model.isEnabled = true
        let secondSaveGate = DispatchSemaphore(value: 0)
        var didQueueRename = false
        model.statusDidChange = {
            guard !didQueueRename, state.saveCompletionCount == 1 else { return }
            didQueueRename = true
            state.saveGate = secondSaveGate
            XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        }
        state.saveGate = nil
        firstSaveGate.signal()
        await waitUntil { state.saveCallCount == 2 }

        XCTAssertTrue(didQueueRename)
        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.canManageProfiles)
        let startedConfigurationsBeforeHandoff = await session.startedConfigurations
        XCTAssertEqual(startedConfigurationsBeforeHandoff.count, 1)

        state.saveGate = nil
        secondSaveGate.signal()
        for _ in 0..<1_000 {
            if model.isRunning, state.saveCompletionCount == 3 { break }
            await Task.yield()
        }
        model.statusDidChange = nil

        let startedConfigurations = await session.startedConfigurations
        let maximumWorkerCount = await session.maximumWorkerCount
        XCTAssertEqual(state.saveCallCount, 3)
        XCTAssertEqual(state.saveCompletionCount, 3)
        XCTAssertEqual(recorder.values, ["start", "save", "stop", "save", "save", "start"])
        XCTAssertEqual(startedConfigurations.map(\.left.sensitivity), [2, 5])
        XCTAssertEqual(maximumWorkerCount, 1)
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.isRunning)
        XCTAssertTrue(model.canManageProfiles)
        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertTrue(model.canToggleOutput)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.activeProfile.name, "Renamed")
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 5)
        XCTAssertEqual(model.activeProfile.configuration.left.sensitivity, 5)
        XCTAssertEqual(state.savedProfileDocument?.profile(id: first.id)?.name, "Renamed")
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.left.sensitivity,
            5
        )
    }

    func testEnableDuringOverlappingSaveCarriesCommitIntentToReplacementLifecycle() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }
        model.isEnabled = true
        model.configuration.left.sensitivity = 5
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { await session.startCount == 2 }

        let startedSensitivity = await session.startedConfigurations.last?.left.sensitivity
        XCTAssertEqual(state.saveCallCount, 2)
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 5)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 5)
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertEqual(startedSensitivity, 5)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testDisablingDuringActivationSaveRecordsPersistedSnapshotWithoutStarting() async {
        let state = readyState(receiver: "Fake")
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        model.configuration.left.sensitivity = 5
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.isEnabled = true
        await waitUntil { state.saveCallCount == 1 }
        model.isEnabled = false
        state.saveGate = nil
        saveGate.signal()
        await waitUntil { state.savedConfiguration?.left.sensitivity == 5 }
        for _ in 0..<100 {
            if model.savedConfiguration.left.sensitivity == 5 { break }
            await Task.yield()
        }

        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 5)
        await waitUntil(model: model) { await session.startCount == 2 }
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isEnabled)
    }

    func testInvalidDraftPreventsSaveAndStart() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.configuration.left.sensitivity = 21

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        await waitUntil(model: model) { await session.startCount == 2 }
        XCTAssertNil(state.savedConfiguration)
        XCTAssertEqual(model.configuration.left.sensitivity, 21)
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected a typed validation failure")
        }
    }

    func testSaveFailurePreventsStartAndPreservesDraft() async {
        let state = readyState(receiver: "Fake")
        state.saveFailure = "disk full"
        let session = ScriptedSession(events: [])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.configuration.left.sensitivity = 6

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        await waitUntil(model: model) { await session.startCount == 2 }
        XCTAssertEqual(model.configuration.left.sensitivity, 6)
        XCTAssertTrue(model.hasUnsavedChanges)
        guard case .failure(.configurationSave) = model.status else {
            return XCTFail("Expected a typed save failure")
        }
    }

    func testSaveAndApplyFailurePreservesDraft() async {
        let state = readyState(receiver: nil)
        state.saveFailure = "disk full"
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 6

        model.saveAndApply()
        await waitUntil(model: model) {
            if case .failure(.configurationSave) = model.status { return true }
            return false
        }

        XCTAssertEqual(model.configuration.left.sensitivity, 6)
        XCTAssertTrue(model.hasUnsavedChanges)
        guard case .failure(.configurationSave) = model.status else {
            return XCTFail("Expected a typed save failure")
        }
    }

    func testSaveAndApplyWhileActiveRestartsFromSavedSnapshot() async {
        let state = readyState(receiver: nil)
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed], keepsStreamOpen: true)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        model.configuration.right.sensitivity = 9
        model.saveAndApply()
        await waitUntil(model: model) { await session.startCount == 2 && model.isRunning }

        let configurations = await session.startedConfigurations
        XCTAssertEqual(configurations.map(\.right.sensitivity), [1, 9])
        XCTAssertEqual(state.savedConfiguration?.right.sensitivity, 9)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testDisablingSupersedesPendingReconnect() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.isEnabled = false
        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }

        await waitUntil(model: model) { await session.startCount == 1 }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .off)
    }

    func testDisconnectedEnableSavesThenReconnectsWithSavedSnapshot() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3)

        model.configuration.left.sensitivity = 5
        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
        XCTAssertEqual(startedSensitivity, 3)
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testRelaunchLoadsConfigurationSavedByEnable() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.right.sensitivity = 8
        model.configuration.left.mouseAcceleration = 0.2
        model.configuration.right.mouseAcceleration = 0.8

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        state.loadedConfiguration = try! XCTUnwrap(state.savedConfiguration)

        let relaunched = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: relaunched) { relaunched.isInitialized }
        XCTAssertEqual(relaunched.configuration.right.sensitivity, 8)
        XCTAssertEqual(relaunched.configuration.left.mouseAcceleration, 0.2)
        XCTAssertEqual(relaunched.configuration.right.mouseAcceleration, 0.8)
        XCTAssertFalse(relaunched.hasUnsavedChanges)
    }

    func testBothPadsRemainZonesAcrossSaveAndRelaunch() async {
        let state = readyState(receiver: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.mode = .dpad
        model.configuration.left.zoneLayout = .horizontalTwo
        model.configuration.left.dpadKeys.left = "q"
        model.configuration.right.mode = .dpad
        model.configuration.right.zoneLayout = .verticalTwo
        model.configuration.right.dpadKeys.up = "e"

        model.saveAndApply()
        await waitUntil(model: model) { model.status == .configurationSaved }
        let saved = try! XCTUnwrap(state.savedConfiguration)
        XCTAssertEqual(saved.left.mode, .dpad)
        XCTAssertEqual(saved.left.zoneLayout, .horizontalTwo)
        XCTAssertEqual(saved.left.dpadKeys.left, "q")
        XCTAssertEqual(saved.right.mode, .dpad)
        XCTAssertEqual(saved.right.zoneLayout, .verticalTwo)
        XCTAssertEqual(saved.right.dpadKeys.up, "e")

        state.loadedConfiguration = saved
        let relaunched = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: relaunched) { relaunched.isInitialized }
        XCTAssertEqual(relaunched.configuration, saved)
        XCTAssertEqual(relaunched.savedConfiguration, saved)
        XCTAssertFalse(relaunched.hasUnsavedChanges)
    }

    func testTerminationAwaitsSessionStop() async {
        let state = readyState(receiver: nil)
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed], keepsStreamOpen: true)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        var didComplete = false
        XCTAssertTrue(model.stopForTermination { didComplete = true })
        await waitUntil(model: model) { didComplete }

        let stopCount = await session.stopCount
        XCTAssertEqual(stopCount, 2)
        XCTAssertEqual(model.status, .releasingOutputs)
    }

    func testTerminationCannotBeSupersededAndRepliesToEveryWaitingRequestOnce() async {
        let state = readyState(receiver: nil)
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        var firstReplyCount = 0
        var secondReplyCount = 0
        XCTAssertTrue(model.stopForTermination { firstReplyCount += 1 })
        await session.waitForStop(2)

        model.isEnabled = false
        model.configuration.left.sensitivity = 4
        model.saveAndApply()
        XCTAssertTrue(model.stopForTermination { secondReplyCount += 1 })
        XCTAssertEqual(firstReplyCount, 0)
        XCTAssertEqual(secondReplyCount, 0)

        await session.releaseStop(2)
        await waitUntil(model: model) { firstReplyCount == 1 && secondReplyCount == 1 }

        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(firstReplyCount, 1)
        XCTAssertEqual(secondReplyCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 2)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.hasPendingLifecycleWork)
    }

    func testTerminationDuringEnableDrainsTheCancelledStartBeforeReplying() async {
        let state = readyState(receiver: nil)
        let session = GatedSession(blockedStops: [1])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await session.waitForStop(1)

        var didReply = false
        XCTAssertTrue(model.stopForTermination { didReply = true })
        await session.waitForStop(2)
        XCTAssertFalse(didReply)

        await session.releaseStop(1)
        await waitUntil(model: model) { didReply }

        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(stopCount, 2)
    }

    func testTerminationDuringDisableDrainsThePendingStop() async {
        let state = readyState(receiver: nil)
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        model.isEnabled = false
        var didReply = false
        XCTAssertTrue(model.stopForTermination { didReply = true })
        await session.waitForStop(2)
        XCTAssertFalse(didReply)

        await session.releaseStop(2)
        await waitUntil(model: model) { didReply }
        let stopCount = await session.stopCount
        XCTAssertEqual(stopCount, 2)
    }

    func testTerminationCancelsPendingReconnect() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = GatedSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                sleeper: sleeper,
                reconnectSleeper: sleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        var didReply = false
        XCTAssertTrue(model.stopForTermination { didReply = true })
        await waitUntil(model: model) { didReply }

        state.receiver = "Late controller"
        sleeper.wake()
        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(stopCount, 2)
    }

    func testTerminationDuringSaveAndApplyPreventsRestart() async {
        let state = readyState(receiver: nil)
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        model.configuration.right.sensitivity = 6
        model.saveAndApply()
        await session.waitForStop(2)
        var didReply = false
        XCTAssertTrue(model.stopForTermination { didReply = true })
        await session.waitForStop(3)
        XCTAssertFalse(didReply)

        await session.releaseStop(2)
        await waitUntil(model: model) { didReply }
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(state.savedConfiguration?.right.sensitivity, 6)
    }

    func testCompletedDisableLeavesNoDeferredTerminationWork() async {
        let state = readyState(receiver: nil)
        let session = GatedSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.isEnabled = false
        await waitUntil(model: model) { model.status == .off }
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }

        var didReply = false
        XCTAssertFalse(model.stopForTermination { didReply = true })
        XCTAssertFalse(didReply)
    }

    func testRestoreDefaultsMarksConfigurationUnsaved() async {
        let state = readyState(receiver: nil)
        var custom = TrackIsBackConfiguration.default
        custom.left.sensitivity = 4
        state.loadedConfiguration = custom
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.restoreDefaults()

        XCTAssertEqual(model.configuration, .default)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .defaultsRestored)
    }

    func testConfigurationLoadFailureUsesDefaultsAndSurfacesError() async {
        let state = readyState(receiver: nil)
        state.loadFailure = "Saved sensitivity is outside the supported range."

        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration, .default)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.needsInitialSave)
        guard case let .failure(.configurationLoad(diagnostic)) = model.status else {
            return XCTFail("Expected a typed load failure")
        }
        XCTAssertEqual(diagnostic, "Saved sensitivity is outside the supported range.")
    }

    func testConfigurationLoadFailureBlocksOverwriteOfRecoverableStorage() async {
        let state = readyState(receiver: nil)
        state.loadFailure = "Saved sensitivity is outside the supported range."
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.saveAndApply()
        await waitUntil(model: model) {
            guard case .failure(.configurationSave) = model.status else { return false }
            return true
        }

        XCTAssertNil(state.savedConfiguration)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.needsInitialSave)
        guard case let .failure(.configurationSave(diagnostic)) = model.status else {
            return XCTFail("Expected storage overwrite protection")
        }
        XCTAssertTrue(diagnostic.contains("Preserve or repair"))
    }

    func testMissingActiveProfileRepairPreservesProfilesAndSurfacesDiagnostic() async throws {
        let state = readyState(receiver: nil)
        var document = ConfigurationProfileDocument.default
        let recoverable = try document.createProfile(
            named: "Recoverable",
            id: ConfigurationProfileID(rawValue: "00000000-0000-0000-0000-000000000203")
        )
        state.loadedProfileDocument = document
        state.loadDiagnostic = "Missing active profile; Default is active."
        let session = ScriptedSession(events: [])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.activeProfileID, .default)
        XCTAssertEqual(model.profiles.first(where: { $0.id == recoverable.id }), recoverable)
        XCTAssertTrue(model.needsInitialSave)
        XCTAssertTrue(model.canSaveAndApply)
        XCTAssertFalse(model.canEditActiveProfile)
        guard case let .failure(.configurationLoad(diagnostic)) = model.status else {
            return XCTFail("Expected the preserved repair diagnostic")
        }
        XCTAssertEqual(diagnostic, state.loadDiagnostic)
        XCTAssertFalse(model.renameActiveProfile(to: "Mutable Default"))
        XCTAssertFalse(model.deleteProfile(id: .default, confirmed: true))

        model.saveAndApply()
        await waitUntil(model: model) { model.status == .configurationSaved }
        XCTAssertEqual(state.savedProfileDocument?.userProfiles, [recoverable])
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, .default)
        XCTAssertFalse(model.needsInitialSave)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.canSaveAndApply)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 0)
    }

    func testEnabledMissingActiveProfileRepairSerializesStopSaveStartAndRearms() async {
        let state = readyState(receiver: "Fake puck")
        state.loadedProfileDocument = .default
        state.loadDiagnostic = "Missing active profile; Default is active."
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let recorder = OperationRecorder()
        state.operationRecorder = recorder
        let session = RecordingSession(recorder: recorder)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil { recorder.values.contains("start") }

        model.isEnabled = true
        XCTAssertTrue(model.canSaveAndApply)
        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }
        XCTAssertEqual(model.profileSelectionPresentation, .active(.default))
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.isRunning && !model.needsInitialSave }

        XCTAssertEqual(recorder.values, ["start", "stop", "save", "start"])
        let maximumWorkerCount = await session.maximumWorkerCount
        XCTAssertEqual(maximumWorkerCount, 1)
        XCTAssertEqual(model.status, .active)
        XCTAssertTrue(model.controllerConnected)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, .default)
    }

    func testProfileSelectionRequiresDiscardConfirmationAndCancelPreservesDraft() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 9

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .configurationWindow),
            .confirmationRequired(second.id)
        )
        XCTAssertEqual(model.profileSelectionPresentation, .active(first.id))
        XCTAssertEqual(
            model.resolveProfileSelection(id: second.id, discardChanges: false),
            .cancelled
        )
        XCTAssertEqual(model.profileSelectionPresentation, .active(first.id))
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration.left.sensitivity, 9)

        XCTAssertEqual(
            model.resolveProfileSelection(id: second.id, discardChanges: true),
            .accepted
        )
        XCTAssertEqual(model.profileSelectionPresentation, .switching(to: second.id, named: second.name))
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration.left.sensitivity, 9)
        await waitUntil(model: model) { model.activeProfileID == second.id }
        XCTAssertEqual(model.profileSelectionPresentation, .active(second.id))
        XCTAssertEqual(model.configuration, second.configuration)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testProfileControlAppearancePreservesCommittedEditabilityUntilSelectionCommits() async throws {
        do {
            let state = readyState(receiver: nil)
            let (document, _, second) = try twoProfileDocument()
            state.loadedProfileDocument = document
            let saveGate = DispatchSemaphore(value: 0)
            state.saveGate = saveGate
            let model = PaddrMenuModel(dependencies: dependencies(state: state))
            await waitUntil(model: model) { model.isInitialized }

            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
            XCTAssertEqual(model.requestProfileSelection(id: second.id, source: .menu), .accepted)
            XCTAssertFalse(model.canEditActiveProfile)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
            state.saveGate = nil
            saveGate.signal()
            await waitUntil(model: model) { model.activeProfileID == second.id }
            XCTAssertTrue(model.canEditActiveProfile)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
        }

        do {
            let state = readyState(receiver: nil)
            let (document, _, _) = try twoProfileDocument()
            state.loadedProfileDocument = document
            let saveGate = DispatchSemaphore(value: 0)
            state.saveGate = saveGate
            let model = PaddrMenuModel(dependencies: dependencies(state: state))
            await waitUntil(model: model) { model.isInitialized }

            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
            XCTAssertEqual(model.requestProfileSelection(id: .default, source: .menu), .accepted)
            XCTAssertFalse(model.canEditActiveProfile)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
            state.saveGate = nil
            saveGate.signal()
            await waitUntil(model: model) { model.activeProfileID == .default }
            XCTAssertFalse(model.canEditActiveProfile)
            XCTAssertFalse(model.activeProfileControlsAppearEnabled)
        }

        do {
            let state = readyState(receiver: nil)
            var (document, _, second) = try twoProfileDocument()
            document.activeProfileID = .default
            state.loadedProfileDocument = document
            let saveGate = DispatchSemaphore(value: 0)
            state.saveGate = saveGate
            let model = PaddrMenuModel(dependencies: dependencies(state: state))
            await waitUntil(model: model) { model.isInitialized }

            XCTAssertFalse(model.activeProfileControlsAppearEnabled)
            XCTAssertEqual(model.requestProfileSelection(id: second.id, source: .menu), .accepted)
            XCTAssertFalse(model.canEditActiveProfile)
            XCTAssertFalse(model.activeProfileControlsAppearEnabled)
            state.saveGate = nil
            saveGate.signal()
            await waitUntil(model: model) { model.activeProfileID == second.id }
            XCTAssertTrue(model.canEditActiveProfile)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
        }
    }

    func testActiveProfileReplacementPresentationCoversCreateDuplicateAndDelete() async throws {
        do {
            let state = readyState(receiver: nil)
            let (document, first, _) = try twoProfileDocument()
            state.loadedProfileDocument = document
            let saveGate = DispatchSemaphore(value: 0)
            state.saveGate = saveGate
            let model = PaddrMenuModel(dependencies: dependencies(state: state))
            await waitUntil(model: model) { model.isInitialized }

            XCTAssertTrue(model.createProfile(named: "Third"))
            guard case let .switching(to: pendingID, named: pendingName) = model.profileSelectionPresentation else {
                state.saveGate = nil
                saveGate.signal()
                return XCTFail("Expected create to present its pending activation")
            }
            XCTAssertEqual(pendingName, "Third")
            XCTAssertNotEqual(pendingID, first.id)
            XCTAssertEqual(model.activeProfileID, first.id)
            XCTAssertEqual(model.profiles, document.profiles)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)
            XCTAssertFalse(model.duplicateActiveProfile())

            state.saveGate = nil
            saveGate.signal()
            await waitUntil(model: model) { model.activeProfileID == pendingID }
            XCTAssertEqual(model.activeProfile.name, "Third")
            XCTAssertEqual(model.profileSelectionPresentation, .active(pendingID))
        }

        do {
            let state = readyState(receiver: nil)
            let (document, first, _) = try twoProfileDocument()
            state.loadedProfileDocument = document
            let saveGate = DispatchSemaphore(value: 0)
            state.saveGate = saveGate
            let model = PaddrMenuModel(dependencies: dependencies(state: state))
            await waitUntil(model: model) { model.isInitialized }

            XCTAssertTrue(model.duplicateActiveProfile())
            guard case let .switching(to: pendingID, named: pendingName) = model.profileSelectionPresentation else {
                state.saveGate = nil
                saveGate.signal()
                return XCTFail("Expected duplicate to present its pending activation")
            }
            XCTAssertEqual(pendingName, "First Copy")
            XCTAssertNotEqual(pendingID, first.id)
            XCTAssertEqual(model.activeProfileID, first.id)
            XCTAssertEqual(model.profiles, document.profiles)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)

            state.saveGate = nil
            saveGate.signal()
            await waitUntil(model: model) { model.activeProfileID == pendingID }
            XCTAssertEqual(model.activeProfile.name, "First Copy")
            XCTAssertEqual(model.profileSelectionPresentation, .active(pendingID))
        }

        do {
            let state = readyState(receiver: nil)
            let (document, first, _) = try twoProfileDocument()
            state.loadedProfileDocument = document
            let saveGate = DispatchSemaphore(value: 0)
            state.saveGate = saveGate
            let model = PaddrMenuModel(dependencies: dependencies(state: state))
            await waitUntil(model: model) { model.isInitialized }

            XCTAssertTrue(model.deleteProfile(id: first.id, confirmed: true))
            XCTAssertEqual(
                model.profileSelectionPresentation,
                .switching(to: .default, named: ConfigurationProfile.default.name)
            )
            XCTAssertEqual(model.activeProfileID, first.id)
            XCTAssertEqual(model.profiles, document.profiles)
            XCTAssertTrue(model.activeProfileControlsAppearEnabled)

            state.saveGate = nil
            saveGate.signal()
            await waitUntil(model: model) { model.activeProfileID == .default }
            XCTAssertEqual(model.profileSelectionPresentation, .active(.default))
            XCTAssertFalse(model.activeProfileControlsAppearEnabled)
        }
    }

    func testMenuProfileSelectionIsBlockedWhileDraftIsUnsaved() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.right.sensitivity = 8

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .blockedByUnsavedChanges
        )
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(state.saveCallCount, 0)
    }

    func testCreateDuplicateRenameAndConfirmedDeletePersistStableProfiles() async throws {
        let state = readyState(receiver: nil)
        state.loadedProfileDocument = .default
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertTrue(model.createProfile(named: "  Gaming  "))
        await waitUntil(model: model) { model.profiles.count == 2 }
        let originalID = model.activeProfileID
        XCTAssertEqual(model.activeProfile.name, "Gaming")

        XCTAssertTrue(model.renameActiveProfile(to: "Arcade"))
        await waitUntil(model: model) { model.activeProfile.name == "Arcade" }
        XCTAssertEqual(model.activeProfileID, originalID)

        XCTAssertTrue(model.duplicateActiveProfile())
        await waitUntil(model: model) { model.profiles.count == 3 }
        let duplicateID = model.activeProfileID
        XCTAssertNotEqual(duplicateID, originalID)
        XCTAssertEqual(model.activeProfile.name, "Arcade Copy")

        XCTAssertFalse(model.deleteProfile(id: duplicateID, confirmed: false))
        XCTAssertEqual(model.activeProfileID, duplicateID)
        XCTAssertTrue(model.deleteProfile(id: originalID, confirmed: true))
        await waitUntil(model: model) { model.profiles.count == 2 }
        XCTAssertEqual(model.activeProfileID, duplicateID)

        XCTAssertTrue(model.deleteProfile(id: duplicateID, confirmed: true))
        await waitUntil(model: model) { model.activeProfileID == .default }
        XCTAssertEqual(model.profiles, [.default])
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, .default)
    }

    func testCreateAndRenameRejectUUIDShapedNamesWithoutPersisting() async throws {
        let createState = readyState(receiver: nil)
        createState.loadedProfileDocument = .default
        let createModel = PaddrMenuModel(dependencies: dependencies(state: createState))
        await waitUntil(model: createModel) { createModel.isInitialized }

        XCTAssertFalse(
            createModel.createProfile(named: " A0000000-0000-0000-0000-000000000040 ")
        )
        XCTAssertEqual(createModel.profiles, [.default])
        XCTAssertEqual(createState.saveCallCount, 0)
        guard case let .failure(.configurationInvalid(createDiagnostic)) = createModel.status else {
            return XCTFail("Expected UUID-shaped create name to publish a validation error")
        }
        XCTAssertTrue(createDiagnostic.contains("cannot be UUIDs"))

        let renameState = readyState(receiver: nil)
        var document = ConfigurationProfileDocument.default
        let profile = try document.createProfile(
            named: "Normal name",
            id: ConfigurationProfileID(rawValue: "b0000000-0000-0000-0000-000000000040")
        )
        try document.activateProfile(id: profile.id)
        renameState.loadedProfileDocument = document
        let renameModel = PaddrMenuModel(dependencies: dependencies(state: renameState))
        await waitUntil(model: renameModel) { renameModel.isInitialized }

        XCTAssertFalse(renameModel.renameActiveProfile(to: profile.id.rawValue.uppercased()))
        XCTAssertEqual(renameModel.activeProfile.name, "Normal name")
        XCTAssertEqual(renameState.saveCallCount, 0)
        guard case let .failure(.configurationInvalid(renameDiagnostic)) = renameModel.status else {
            return XCTFail("Expected UUID-shaped rename to publish a validation error")
        }
        XCTAssertTrue(renameDiagnostic.contains("cannot be UUIDs"))
    }

    func testProfileSelectionSaveFailureDisablesOutputEnabledDuringPersistence() async throws {
        let state = readyState(receiver: "Fake puck")
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        state.saveFailure = "simulated profile activation save failure"
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = GatedSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        XCTAssertEqual(model.profileSelectionPresentation, .switching(to: second.id, named: second.name))
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration, first.configuration)
        await waitUntil { state.saveCallCount == 1 }
        model.isEnabled = true
        XCTAssertTrue(model.isEnabled)

        saveGate.signal()
        await waitUntil(model: model) {
            state.saveCompletionCount == 1 && model.canManageProfiles && !model.isEnabled
        }
        await waitUntil(model: model) { await session.startCount == 2 }

        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.profileSelectionPresentation, .active(first.id))
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration, first.configuration)
        XCTAssertEqual(model.savedConfiguration, first.configuration)
        XCTAssertNil(state.savedProfileDocument)
        guard case let .failure(.configurationSave(diagnostic)) = model.status else {
            return XCTFail("Expected the profile activation save failure, got \(model.status)")
        }
        XCTAssertTrue(diagnostic.contains("simulated profile activation save failure"))
        await session.stop()
        guard case .failure(.configurationSave) = model.status else {
            return XCTFail("Expected the profile activation save failure to remain authoritative")
        }
    }

    func testEnabledProfileSelectionSerializesStopSaveStartWithoutWorkerOverlap() async throws {
        let state = readyState(receiver: "Fake")
        let (document, _, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let recorder = OperationRecorder()
        state.operationRecorder = recorder
        let session = RecordingSession(recorder: recorder)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }
        recorder.removeAll()

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        await waitUntil(model: model) {
            model.activeProfileID == second.id && model.isRunning
        }

        let maximumWorkerCount = await session.maximumWorkerCount
        let startedConfiguration = await session.startedConfigurations.last
        XCTAssertEqual(recorder.values, ["stop", "save", "start"])
        XCTAssertEqual(maximumWorkerCount, 1)
        XCTAssertEqual(startedConfiguration, second.configuration)
    }

    func testEnabledProfileSelectionPersistsWhenOutputIsDisabledDuringStop() async throws {
        let state = readyState(receiver: nil)
        let (document, _, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        XCTAssertEqual(model.profileSelectionPresentation, .switching(to: second.id, named: second.name))
        await session.waitForStop(2)
        model.isEnabled = false
        XCTAssertEqual(model.profileSelectionPresentation, .switching(to: second.id, named: second.name))
        await session.releaseStop(2)
        await waitUntil(model: model) {
            state.saveCompletionCount == 1 && model.activeProfileID == second.id
        }
        await waitUntil(model: model) { await session.startCount == 2 }

        XCTAssertEqual(state.saveCompletionCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .off)
        XCTAssertEqual(model.profileSelectionPresentation, .active(second.id))
        XCTAssertEqual(model.activeProfileID, second.id)
        XCTAssertEqual(model.configuration, second.configuration)
        XCTAssertEqual(model.savedConfiguration, second.configuration)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, second.id)
    }

    func testEnabledActiveProfileDeletionPersistsWhenOutputIsDisabledDuringStop() async throws {
        let state = readyState(receiver: nil)
        let (document, first, _) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        XCTAssertTrue(model.deleteProfile(id: first.id, confirmed: true))
        await session.waitForStop(2)
        model.isEnabled = false
        await session.releaseStop(2)
        for _ in 0..<1_000 where state.saveCompletionCount == 0 {
            await Task.yield()
        }

        await waitUntil(model: model) { await session.startCount == 2 }
        XCTAssertEqual(state.saveCompletionCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .off)
        XCTAssertFalse(model.profiles.contains(where: { $0.id == first.id }))
        XCTAssertEqual(model.activeProfileID, .default)
        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(model.savedConfiguration, .default)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, .default)
    }

    func testEnabledProfileRepairPersistsWhenOutputIsDisabledDuringStop() async {
        let state = readyState(receiver: "Fake")
        state.loadedProfileDocument = .default
        state.loadDiagnostic = "Missing active profile; Default is active."
        let session = GatedSession(blockedStops: [1])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        model.isEnabled = true
        model.saveAndApply()
        await session.waitForStop(1)
        model.isEnabled = false
        await session.releaseStop(1)
        for _ in 0..<1_000 where state.saveCompletionCount == 0 {
            await Task.yield()
        }

        await waitUntil(model: model) { await session.startCount == 2 }
        XCTAssertEqual(state.saveCompletionCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .off)
        XCTAssertFalse(model.needsInitialSave)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.activeProfileID, .default)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, .default)
    }

    func testProfileSelectionReenabledDuringStopRestartsExactlyOnceAfterPersistence() async throws {
        let state = readyState(receiver: nil)
        let (document, _, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        await session.waitForStop(2)
        model.isEnabled = false
        model.isEnabled = true
        await session.releaseStop(2)
        await waitUntil(model: model) { state.saveCompletionCount == 1 }
        await waitUntil(model: model) { await session.startCount == 2 }
        await waitUntil(model: model) { model.isRunning }

        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 2)
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.status, .active)
        XCTAssertEqual(model.activeProfileID, second.id)
        XCTAssertEqual(model.savedConfiguration, second.configuration)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, second.id)
    }

    func testProfileSelectionReenabledAfterSaveRestartsExactlyOnce() async throws {
        let state = readyState(receiver: nil)
        let (document, _, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        await session.waitForStop(2)
        model.isEnabled = false
        await session.releaseStop(2)
        await waitUntil { state.saveCallCount == 1 }
        saveGate.signal()
        await waitUntil(model: model) { model.activeProfileID == second.id }
        await waitUntil(model: model) { await session.startCount == 2 }
        await waitUntil(model: model) { model.controllerConnected }

        model.isEnabled = true
        await waitUntil(model: model) {
            model.status == .waitingForNeutral || model.status == .active
        }

        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 2)
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.controllerConnected)
        XCTAssertEqual(model.savedConfiguration, second.configuration)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, second.id)
    }

    func testTerminationDuringProfileSelectionPreventsStalePublicationAndRestart() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = GatedSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        state.receiver = "Fake"
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        await waitUntil { state.saveCallCount == 1 }
        XCTAssertEqual(model.profileSelectionPresentation, .switching(to: second.id, named: second.name))

        var didComplete = false
        XCTAssertTrue(model.stopForTermination { didComplete = true })
        XCTAssertEqual(model.profileSelectionPresentation, .switching(to: second.id, named: second.name))
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { didComplete }

        let startCount = await session.startCount
        XCTAssertEqual(state.saveCallCount, 1)
        XCTAssertEqual(state.saveCompletionCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .releasingOutputs)
        XCTAssertEqual(model.profileSelectionPresentation, .active(first.id))
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.configuration, first.configuration)
        XCTAssertEqual(model.savedConfiguration, first.configuration)
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, second.id)
        await Task.yield()
        XCTAssertEqual(model.profileSelectionPresentation, .active(first.id))
        XCTAssertEqual(model.activeProfileID, first.id)
    }

    func testEnabledProfileSelectionRejectsOldSessionEventsAndReestablishesLivenessAuthority() async throws {
        let state = readyState(receiver: "Fake puck")
        let (document, _, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = RetainedEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.send(.waitingForController("Fake puck"), to: 0)
        await session.send(.controllerConnected, to: 0)
        await session.send(.outputArmed, to: 0)
        await waitUntil(model: model) { model.status == .active }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        await waitUntil { state.saveCallCount == 1 }

        XCTAssertEqual(model.status, .releasingOutputs)
        XCTAssertEqual(model.receiverDescription, "Fake puck")
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        await session.waitForTermination(of: 0)
        await session.send(.failed("stale session"), to: 0)
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.status, .releasingOutputs)

        saveGate.signal()
        await waitUntil(model: model) { await session.startCount == 2 }
        XCTAssertEqual(model.activeProfileID, second.id)
        XCTAssertEqual(model.status, .connecting)
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        await session.send(.waitingForController("Fake puck"), to: 1)
        await waitUntil(model: model) { model.status == .waitingForController }
        XCTAssertEqual(model.receiverDescription, "Fake puck")
        XCTAssertFalse(model.controllerConnected)

        model.configuration.left.sensitivity = 3
        await session.send(.controllerConnected, to: 1)
        await waitUntil(model: model) { model.status == .waitingForNeutral }
        XCTAssertTrue(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        await session.send(.outputArmed, to: 1)
        await waitUntil(model: model) { model.status == .active }
        XCTAssertTrue(model.isRunning)
        await session.finishAll()
    }

    func testProfileRenameCompletionPreservesCurrentSessionLivenessAuthority() async throws {
        let state = readyState(receiver: "Fake puck")
        let (document, _, _) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake puck")
        await waitUntil(model: model) { model.status == .active }

        XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        await waitUntil { state.saveCallCount == 1 }
        await session.send(.controllerLost(.init(reportCount: 1, actionCount: 0)))
        await waitUntil(model: model) { model.status == .waitingForController }

        saveGate.signal()
        await waitUntil(model: model) { model.activeProfile.name == "Renamed" }
        XCTAssertEqual(model.status, .waitingForController)
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        model.configuration.right.sensitivity = 7
        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.status == .waitingForNeutral }
        await session.send(.outputArmed)
        await waitUntil(model: model) { model.status == .active }
        XCTAssertTrue(model.isRunning)
    }

    func testProfileSelectionRejectsSecondRequestWhileActivationWorkIsPending() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        XCTAssertEqual(
            model.requestProfileSelection(id: first.id, source: .menu),
            .operationInProgress
        )
        saveGate.signal()
        await waitUntil(model: model) { model.activeProfileID == second.id }
        XCTAssertEqual(state.savedProfileDocument?.activeProfileID, second.id)
    }

    func testProfileSelectionRejectsMutationsWhileActivationWorkIsPendingThenReenablesEditing() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .accepted
        )
        await waitUntil { state.saveCallCount == 1 }

        XCTAssertFalse(model.canEditActiveProfile)
        XCTAssertTrue(model.activeProfileControlsAppearEnabled)
        XCTAssertFalse(model.canManageProfiles)
        XCTAssertFalse(model.canSaveAndApply)
        model.configuration.left.sensitivity = 9
        model.restoreDefaults()
        model.saveAndApply()
        XCTAssertFalse(model.createProfile(named: "Racing"))
        XCTAssertFalse(model.duplicateActiveProfile())
        XCTAssertFalse(model.renameActiveProfile(to: "Renamed"))
        XCTAssertFalse(model.deleteProfile(id: first.id, confirmed: true))
        XCTAssertEqual(
            model.requestProfileSelection(id: first.id, source: .menu),
            .operationInProgress
        )
        XCTAssertEqual(model.configuration, first.configuration)
        XCTAssertEqual(model.activeProfileID, first.id)
        XCTAssertEqual(model.profiles, document.profiles)
        XCTAssertEqual(state.saveCallCount, 1)

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.activeProfileID == second.id }

        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertTrue(model.canManageProfiles)
        XCTAssertEqual(model.configuration, second.configuration)
        model.configuration.left.sensitivity = 7
        model.saveAndApply()
        await waitUntil { state.saveCallCount == 2 }
        await waitUntil(model: model) { !model.hasUnsavedChanges }
        XCTAssertEqual(state.savedProfileDocument?.activeProfile?.configuration.left.sensitivity, 7)
    }

    func testDocumentOnlyProfileSaveDoesNotFreezeOrOverwritePadEditing() async throws {
        let state = readyState(receiver: nil)
        let (document, _, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        await waitUntil { state.saveCallCount == 1 }
        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertFalse(model.canManageProfiles)
        model.configuration.left.sensitivity = 8
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.activeProfile.name == "Renamed" }
        XCTAssertEqual(model.configuration.left.sensitivity, 8)
        XCTAssertTrue(model.hasUnsavedChanges)

        let inactiveID = second.id
        let deleteGate = DispatchSemaphore(value: 0)
        state.saveGate = deleteGate
        XCTAssertTrue(model.deleteProfile(id: inactiveID, confirmed: true))
        await waitUntil { state.saveCallCount == 2 }
        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertFalse(model.canManageProfiles)
        model.configuration.left.sensitivity = 9
        state.saveGate = nil
        deleteGate.signal()
        await waitUntil(model: model) { !model.profiles.contains(where: { $0.id == inactiveID }) }
        XCTAssertEqual(model.configuration.left.sensitivity, 9)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testPendingRenameBlocksPersistenceSupersessionWhilePadEditingRemainsAvailable() async throws {
        let state = readyState(receiver: "Fake puck")
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = ScriptedSession(events: [])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        await waitUntil { state.saveCallCount == 1 }
        model.configuration.left.sensitivity = 8

        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertFalse(model.canSaveAndApply)
        model.saveAndApply()
        model.isEnabled = true
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .operationInProgress
        )
        XCTAssertEqual(state.saveCallCount, 1)

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.canManageProfiles }

        XCTAssertEqual(state.saveCallCount, 1)
        XCTAssertEqual(state.savedProfileDocument?.profile(id: first.id)?.name, "Renamed")
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.left.sensitivity,
            first.configuration.left.sensitivity
        )
        XCTAssertEqual(model.configuration.left.sensitivity, 8)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.canSaveAndApply)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)

        model.saveAndApply()
        await waitUntil(model: model) { !model.hasUnsavedChanges }
        XCTAssertEqual(state.saveCallCount, 2)
        XCTAssertEqual(state.savedProfileDocument?.profile(id: first.id)?.name, "Renamed")
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.left.sensitivity,
            8
        )
    }

    func testEnabledDirtyActivationCommitSerializesRenameWithoutStaleOverwrite() async throws {
        let state = readyState(receiver: "Fake puck")
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let session = GatedSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 9

        model.isEnabled = true
        await waitUntil { state.saveCallCount == 1 }

        XCTAssertFalse(model.canManageProfiles)
        XCTAssertFalse(model.createProfile(named: "New profile"))
        XCTAssertFalse(model.duplicateActiveProfile())
        XCTAssertFalse(model.renameActiveProfile(to: "Renamed"))
        XCTAssertFalse(model.deleteProfile(id: second.id, confirmed: true))
        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .menu),
            .operationInProgress
        )
        XCTAssertEqual(model.profiles, document.profiles)
        XCTAssertEqual(state.saveCallCount, 1)

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) {
            model.isRunning && !model.hasUnsavedChanges && model.canManageProfiles
        }

        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 9)
        XCTAssertEqual(model.configuration.left.sensitivity, 9)
        XCTAssertEqual(model.activeProfile.name, first.name)
        XCTAssertEqual(model.activeProfile.configuration.left.sensitivity, 9)
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.left.sensitivity,
            9
        )

        XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        await waitUntil(model: model) {
            model.activeProfile.name == "Renamed" && state.saveCompletionCount == 2
        }

        XCTAssertTrue(model.canManageProfiles)
        XCTAssertTrue(model.canEditActiveProfile)
        XCTAssertTrue(model.canToggleOutput)
        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 9)
        XCTAssertEqual(model.configuration.left.sensitivity, 9)
        XCTAssertEqual(model.activeProfile.configuration.left.sensitivity, 9)
        XCTAssertEqual(state.savedProfileDocument?.profile(id: first.id)?.name, "Renamed")
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.left.sensitivity,
            9
        )
    }

    func testPendingInactiveDeleteCannotBeRestoredBySaveAndApply() async throws {
        let state = readyState(receiver: nil)
        let (document, first, second) = try twoProfileDocument()
        state.loadedProfileDocument = document
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertTrue(model.deleteProfile(id: second.id, confirmed: true))
        await waitUntil { state.saveCallCount == 1 }
        model.configuration.right.sensitivity = 9

        XCTAssertFalse(model.canSaveAndApply)
        model.saveAndApply()
        XCTAssertEqual(
            model.requestProfileSelection(id: second.id, source: .configurationWindow),
            .operationInProgress
        )
        XCTAssertEqual(state.saveCallCount, 1)

        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { model.canManageProfiles }

        XCTAssertEqual(state.saveCallCount, 1)
        XCTAssertNil(state.savedProfileDocument?.profile(id: second.id))
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.right.sensitivity,
            first.configuration.right.sensitivity
        )
        XCTAssertEqual(model.configuration.right.sensitivity, 9)
        XCTAssertTrue(model.hasUnsavedChanges)

        model.saveAndApply()
        await waitUntil(model: model) { !model.hasUnsavedChanges }
        XCTAssertEqual(state.saveCallCount, 2)
        XCTAssertNil(state.savedProfileDocument?.profile(id: second.id))
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.right.sensitivity,
            9
        )
    }

    func testFailedDocumentOnlySavePreservesDraftAndCanRetryMetadataBeforeApplying() async throws {
        let state = readyState(receiver: nil)
        let (document, first, _) = try twoProfileDocument()
        state.loadedProfileDocument = document
        state.saveFailure = "simulated metadata save failure"
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.configuration.left.sensitivity = 9
        XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        await waitUntil(model: model) {
            if case .failure(.configurationSave) = model.status {
                return model.canManageProfiles
            }
            return false
        }

        XCTAssertEqual(state.saveCompletionCount, 1)
        XCTAssertEqual(model.activeProfile.name, first.name)
        XCTAssertEqual(model.configuration.left.sensitivity, 9)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNil(state.savedProfileDocument)
        guard case let .failure(.configurationSave(diagnostic)) = model.status else {
            return XCTFail("Expected the metadata save failure, got \(model.status)")
        }
        XCTAssertTrue(diagnostic.contains("simulated metadata save failure"))

        state.saveFailure = nil
        XCTAssertTrue(model.renameActiveProfile(to: "Renamed"))
        await waitUntil(model: model) { model.activeProfile.name == "Renamed" }
        XCTAssertEqual(state.saveCompletionCount, 2)
        XCTAssertEqual(model.configuration.left.sensitivity, 9)
        XCTAssertTrue(model.hasUnsavedChanges)

        model.saveAndApply()
        await waitUntil(model: model) { !model.hasUnsavedChanges }
        XCTAssertEqual(state.saveCompletionCount, 3)
        XCTAssertEqual(state.savedProfileDocument?.profile(id: first.id)?.name, "Renamed")
        XCTAssertEqual(
            state.savedProfileDocument?.profile(id: first.id)?.configuration.left.sensitivity,
            9
        )
    }

    func testControllerReportsWhileDisabledShowControllerConnectedWithoutOutput() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }

        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(model.controllerConnected)
        XCTAssertNotNil(model.receiverDescription)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isReleasingOutput)
        XCTAssertEqual(model.status, .off)
    }

    func testDisableReleasesHeldOutputBeforeOutputBecomesIdleAndRetainsController() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.isRunning }

        model.isEnabled = false

        XCTAssertTrue(model.isReleasingOutput)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .releasingOutputs)
        XCTAssertTrue(model.controllerConnected)

        await session.send(.outputReleased)
        await waitUntil(model: model) { !model.isReleasingOutput }

        XCTAssertEqual(model.status, .off)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.controllerConnected)
        XCTAssertNotNil(model.receiverDescription)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testEnableWithLiveObservationSessionFlipsGateInPlaceWithoutRestart() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }

        model.isEnabled = true

        XCTAssertTrue(model.controllerConnected)
        XCTAssertEqual(model.status, .waitingForNeutral)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)

        await session.send(.outputArmed)
        await waitUntil(model: model) { model.isRunning }
        XCTAssertEqual(model.status, .active)
    }

    func testEnableIsRejectedWhileOutputReleaseIsPending() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.isRunning }

        model.isEnabled = false
        XCTAssertTrue(model.isReleasingOutput)
        XCTAssertFalse(model.canToggleOutput)

        model.isEnabled = true
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.status, .releasingOutputs)

        await session.send(.outputReleased)
        await waitUntil(model: model) { !model.isReleasingOutput }
        XCTAssertEqual(model.status, .off)
        XCTAssertTrue(model.canToggleOutput)

        model.isEnabled = true
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.status, .waitingForNeutral)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testDisableOfLiveSessionAwaitsWorkerAcknowledgementEvenWhenUnarmed() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        XCTAssertFalse(model.isRunning)

        model.isEnabled = false

        XCTAssertTrue(model.isReleasingOutput)
        XCTAssertEqual(model.status, .releasingOutputs)
        model.isEnabled = true
        XCTAssertFalse(model.isEnabled)

        await session.send(.outputReleased)
        await waitUntil(model: model) { !model.isReleasingOutput }
        XCTAssertEqual(model.status, .off)
        XCTAssertTrue(model.canToggleOutput)
    }

    func testOutputFailureKeepsObservationAliveThroughReconnect() async {
        let state = readyState(receiver: "Fake receiver")
        let reconnectSleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                reconnectSleeper: reconnectSleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.isRunning }

        await session.send(.failed("dispatch failed"))
        await waitUntil(model: model) { !model.isEnabled }
        guard case .failure(.output) = model.status else {
            return XCTFail("Expected the output failure to publish")
        }

        reconnectSleeper.wake()
        await waitUntil(model: model) { await session.startCount == 2 }
        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }

        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        guard case .failure(.output) = model.status else {
            return XCTFail("Expected the failure diagnostic to survive the observation restart")
        }
    }

    func testControllerLossDuringReleaseCompletesToIdle() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        model.isEnabled = true
        await session.connect(receiver: "Fake receiver")
        await waitUntil(model: model) { model.isRunning }

        model.isEnabled = false
        XCTAssertEqual(model.status, .releasingOutputs)

        await session.send(.controllerLost(.init(reportCount: 4, actionCount: 2)))
        await waitUntil(model: model) { !model.controllerConnected }

        XCTAssertFalse(model.isReleasingOutput)
        XCTAssertEqual(model.status, .off)
        XCTAssertNotNil(model.receiverDescription)

        await session.send(.outputReleased)
        await session.send(.progress(.init(reportCount: 9, actionCount: 0)))
        await waitUntil(model: model) { model.reportCount == 9 }
        XCTAssertEqual(model.status, .off)
    }

    func testNoPuckStartupDetectsHotPlugWhileDisabled() async {
        let state = readyState(receiver: nil)
        let reconnectSleeper = ManualSleeper()
        let session = ManualEventSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                state: state,
                session: session,
                reconnectSleeper: reconnectSleeper
            )
        )
        await waitUntil(model: model) { model.isInitialized }
        XCTAssertNil(model.receiverDescription)
        let preHotPlugStartCount = await session.startCount
        XCTAssertEqual(preHotPlugStartCount, 0)

        state.receiver = "Hot-plugged puck"
        reconnectSleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }

        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.receiverDescription, "Hot-plugged puck")
        XCTAssertEqual(model.status, .off)

        await session.send(.controllerConnected)
        await waitUntil(model: model) { model.controllerConnected }
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .off)
    }

    func testReceiverOpenFailureKeepsProbeSourcedPuckPresence() async {
        let state = readyState(receiver: "Probe-visible puck")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        await waitUntil(model: model) { await session.startCount == 1 }
        XCTAssertEqual(model.receiverDescription, "Probe-visible puck")

        await session.send(.receiverUnavailable("open failed"))
        await session.stop()
        await waitUntil(model: model) { !model.hasPendingLifecycleWork }

        XCTAssertEqual(model.receiverDescription, "Probe-visible puck")
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.status, .off)
    }

    func testDroppedModelIsNotRetainedByLiveSessionStream() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        var model: PaddrMenuModel? = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session)
        )
        weak let droppedModel = model
        if let model {
            await waitUntil(model: model) { model.isInitialized }
            await waitUntil(model: model) { await session.startCount == 1 }
        }

        model = nil
        for _ in 0..<1_000 {
            if droppedModel == nil { break }
            await session.send(.progress(.init(reportCount: 1, actionCount: 0)))
            await Task.yield()
        }

        XCTAssertNil(droppedModel)
        await session.stop()
    }

    private func twoProfileDocument() throws -> (
        ConfigurationProfileDocument,
        ConfigurationProfile,
        ConfigurationProfile
    ) {
        var firstConfiguration = TrackIsBackConfiguration.default
        firstConfiguration.left.sensitivity = 2
        var secondConfiguration = TrackIsBackConfiguration.default
        secondConfiguration.right.sensitivity = 6
        var document = ConfigurationProfileDocument.default
        let first = try document.createProfile(
            named: "First",
            configuration: firstConfiguration,
            id: ConfigurationProfileID(rawValue: "00000000-0000-0000-0000-000000000201")
        )
        let second = try document.createProfile(
            named: "Second",
            configuration: secondConfiguration,
            id: ConfigurationProfileID(rawValue: "00000000-0000-0000-0000-000000000202")
        )
        document.activeProfileID = first.id
        return (document, first, second)
    }

    private func readyState(receiver: String?) -> ModelDependencyState {
        let state = ModelDependencyState()
        state.accessibilityGranted = true
        state.receiver = receiver
        return state
    }

    private func dependencies(
        state: ModelDependencyState,
        session: any TrackpadSessionControlling = ScriptedSession(events: []),
        sleeper: ManualSleeper? = nil,
        reconnectSleeper: ManualSleeper? = nil
    ) -> MenuDependencies {
        MenuDependencies(
            session: session,
            loadProfiles: {
                state.loadGate?.wait()
                state.loadRanOnMainThread = Thread.isMainThread
                if let failure = state.loadFailure {
                    throw TrackIsBackError.configuration(failure)
                }
                if let document = state.loadedProfileDocument {
                    return ConfigurationProfileLoadResult(
                        document: document,
                        diagnostic: state.loadDiagnostic
                    )
                }
                var document = ConfigurationProfileDocument.default
                let profile = try document.createProfile(
                    named: "Loaded",
                    configuration: state.loadedConfiguration,
                    id: ConfigurationProfileID(
                        rawValue: "00000000-0000-0000-0000-000000000101"
                    )
                )
                document.activeProfileID = profile.id
                return ConfigurationProfileLoadResult(document: document)
            },
            saveProfiles: {
                state.saveCallCount += 1
                defer { state.saveCompletionCount += 1 }
                state.saveGate?.wait()
                if let failure = state.saveFailure {
                    throw TrackIsBackError.configuration(failure)
                }
                state.operationRecorder?.record("save")
                state.savedProfileDocument = $0
                state.savedConfiguration = $0.activeProfile?.configuration
            },
            probeReceiver: {
                state.probeCallCount += 1
                state.probeGate?.wait()
                return state.receiver
            },
            accessibilityTrusted: { prompt in
                state.accessibilityPromptValues.append(prompt)
                return state.accessibilityGranted
            },
            openPrivacySettings: { state.openedPrivacySettingsAnchors.append($0) },
            sleep: { _ in
                guard let sleeper else { throw CancellationError() }
                try await sleeper.sleep()
            },
            reconnectDelay: { _ in
                guard let reconnectSleeper else { throw CancellationError() }
                try await reconnectSleeper.sleep()
            }
        )
    }

    private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    private func waitUntil(
        model: PaddrMenuModel,
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        if await condition() { return }
        let (changes, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        model.statusDidChange = { continuation.yield(()) }
        defer {
            model.statusDidChange = nil
            continuation.finish()
        }
        if await condition() { return }
        for await _ in changes {
            if await condition() { return }
        }
    }
}

private actor ProgressPressureSession: TrackpadSessionControlling {
    private let runtime: MenuProgressPressureRuntime
    private let session: TrackpadSession

    init() {
        let runtime = MenuProgressPressureRuntime()
        self.runtime = runtime
        session = TrackpadSession(runtime: runtime.run)
    }

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        let stream = await session.start(configuration: configuration, observeOnly: observeOnly)
        await runtime.waitUntilProduced()
        return stream
    }

    func stop() async {
        runtime.release()
        await session.stop()
    }
}

private final class MenuProgressPressureRuntime: Sendable {
    private let produced: AsyncStream<Void>
    private let producedContinuation: AsyncStream<Void>.Continuation
    private let releaseGate = DispatchSemaphore(value: 0)

    init() {
        (produced, producedContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    func run(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?,
        stopToken: TrackpadStopToken,
        event: @escaping @Sendable (TrackpadSessionEvent) -> Void
    ) throws -> TrackpadRunResult {
        event(.waitingForController("pressure-test"))
        event(.controllerConnected)
        event(.outputArmed)
        for reportCount in 1...40 {
            event(.progress(.init(reportCount: reportCount, actionCount: reportCount / 10)))
        }
        event(.controllerLost(.init(reportCount: 40, actionCount: 4)))
        event(.controllerConnected)
        event(.outputArmed)
        for reportCount in 41...80 {
            event(.progress(.init(reportCount: reportCount, actionCount: reportCount / 10)))
        }
        producedContinuation.yield(())
        releaseGate.wait()
        return TrackpadRunResult(
            summary: .init(reportCount: 80, actionCount: 8),
            termination: .stopped
        )
    }

    func waitUntilProduced() async {
        var iterator = produced.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        releaseGate.signal()
    }
}

private actor ScriptedSession: TrackpadSessionControlling {
    private let events: [TrackpadSessionEvent]
    private let keepsStreamOpen: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var startedConfigurations: [TrackIsBackConfiguration] = []
    private var continuation: AsyncStream<TrackpadSessionEvent>.Continuation?

    init(events: [TrackpadSessionEvent], keepsStreamOpen: Bool = false) {
        self.events = events
        self.keepsStreamOpen = keepsStreamOpen
    }

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        startCount += 1
        startedConfigurations.append(configuration)
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        for event in events { continuation.yield(event) }
        if keepsStreamOpen {
            self.continuation = continuation
        } else {
            continuation.finish()
        }
        return stream
    }

    func stop() async {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }
}

private actor ManualEventSession: TrackpadSessionControlling {
    private var continuation: AsyncStream<TrackpadSessionEvent>.Continuation?
    private(set) var startCount = 0

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        startCount += 1
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        self.continuation = continuation
        return stream
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
    }

    func send(_ event: TrackpadSessionEvent) {
        continuation?.yield(event)
    }

    func connect(receiver description: String) {
        continuation?.yield(.waitingForController(description))
        continuation?.yield(.controllerConnected)
        continuation?.yield(.outputArmed)
    }
}

private actor RetainedEventSession: TrackpadSessionControlling {
    private let terminationGate = IndexedStopGate()
    private var continuations: [AsyncStream<TrackpadSessionEvent>.Continuation] = []
    private(set) var startCount = 0

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        startCount += 1
        let index = continuations.count
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        continuation.onTermination = { [terminationGate] _ in
            Task { await terminationGate.release(index) }
        }
        continuations.append(continuation)
        return stream
    }

    func stop() async {}

    func send(_ event: TrackpadSessionEvent, to index: Int) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].yield(event)
    }

    func waitForTermination(of index: Int) async {
        await terminationGate.wait(for: index)
    }

    func finishAll() {
        for continuation in continuations { continuation.finish() }
    }
}

private actor GatedSession: TrackpadSessionControlling {
    private let blockedStops: Set<Int>
    private let gate = IndexedStopGate()
    private let stopEvents: AsyncStream<Int>
    private let stopEventsContinuation: AsyncStream<Int>.Continuation
    private var eventContinuation: AsyncStream<TrackpadSessionEvent>.Continuation?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(blockedStops: Set<Int> = []) {
        self.blockedStops = blockedStops
        (stopEvents, stopEventsContinuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
    }

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        startCount += 1
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        eventContinuation = continuation
        continuation.yield(.waitingForController("Fake puck"))
        continuation.yield(.controllerConnected)
        continuation.yield(.outputArmed)
        return stream
    }

    func stop() async {
        stopCount += 1
        let stopNumber = stopCount
        stopEventsContinuation.yield(stopNumber)
        if blockedStops.contains(stopNumber) {
            await gate.wait(for: stopNumber)
        }
        eventContinuation?.finish()
        eventContinuation = nil
    }

    func waitForStop(_ expectedCount: Int) async {
        if stopCount >= expectedCount { return }
        for await count in stopEvents where count >= expectedCount { return }
    }

    func releaseStop(_ stopNumber: Int) async {
        await gate.release(stopNumber)
    }
}

private actor IndexedStopGate {
    private var released: Set<Int> = []
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func wait(for index: Int) async {
        if released.remove(index) != nil { return }
        await withCheckedContinuation { continuation in
            waiters[index, default: []].append(continuation)
        }
    }

    func release(_ index: Int) {
        guard let continuations = waiters.removeValue(forKey: index) else {
            released.insert(index)
            return
        }
        for continuation in continuations { continuation.resume() }
    }
}

private final class ModelDependencyState: Sendable {
    private struct State: ~Copyable {
        var loadedConfiguration = TrackIsBackConfiguration.default
        var loadedProfileDocument: ConfigurationProfileDocument?
        var savedConfiguration: TrackIsBackConfiguration?
        var savedProfileDocument: ConfigurationProfileDocument?
        var receiver: String?
        var openedPrivacySettingsAnchors: [String] = []
        var accessibilityGranted = false
        var accessibilityPromptValues: [Bool] = []
        var loadFailure: String?
        var loadDiagnostic: String?
        var loadGate: DispatchSemaphore?
        var loadRanOnMainThread: Bool?
        var saveFailure: String?
        var saveGate: DispatchSemaphore?
        var saveCallCount = 0
        var saveCompletionCount = 0
        var probeCallCount = 0
        var probeGate: DispatchSemaphore?
        var operationRecorder: OperationRecorder?
        var statusChangeCount = 0
    }
    private let state = Mutex(State())

    var loadedConfiguration: TrackIsBackConfiguration {
        get { state.withLock { $0.loadedConfiguration } }
        set { state.withLock { $0.loadedConfiguration = newValue } }
    }
    var loadedProfileDocument: ConfigurationProfileDocument? {
        get { state.withLock { $0.loadedProfileDocument } }
        set { state.withLock { $0.loadedProfileDocument = newValue } }
    }
    var savedConfiguration: TrackIsBackConfiguration? {
        get { state.withLock { $0.savedConfiguration } }
        set { state.withLock { $0.savedConfiguration = newValue } }
    }
    var savedProfileDocument: ConfigurationProfileDocument? {
        get { state.withLock { $0.savedProfileDocument } }
        set { state.withLock { $0.savedProfileDocument = newValue } }
    }
    var receiver: String? {
        get { state.withLock { $0.receiver } }
        set { state.withLock { $0.receiver = newValue } }
    }
    var openedPrivacySettingsAnchors: [String] {
        get { state.withLock { $0.openedPrivacySettingsAnchors } }
        set { state.withLock { $0.openedPrivacySettingsAnchors = newValue } }
    }
    var accessibilityGranted: Bool {
        get { state.withLock { $0.accessibilityGranted } }
        set { state.withLock { $0.accessibilityGranted = newValue } }
    }
    var accessibilityPromptValues: [Bool] {
        get { state.withLock { $0.accessibilityPromptValues } }
        set { state.withLock { $0.accessibilityPromptValues = newValue } }
    }
    var loadFailure: String? {
        get { state.withLock { $0.loadFailure } }
        set { state.withLock { $0.loadFailure = newValue } }
    }
    var loadDiagnostic: String? {
        get { state.withLock { $0.loadDiagnostic } }
        set { state.withLock { $0.loadDiagnostic = newValue } }
    }
    var loadGate: DispatchSemaphore? {
        get { state.withLock { $0.loadGate } }
        set { state.withLock { $0.loadGate = newValue } }
    }
    var loadRanOnMainThread: Bool? {
        get { state.withLock { $0.loadRanOnMainThread } }
        set { state.withLock { $0.loadRanOnMainThread = newValue } }
    }
    var saveFailure: String? {
        get { state.withLock { $0.saveFailure } }
        set { state.withLock { $0.saveFailure = newValue } }
    }
    var saveGate: DispatchSemaphore? {
        get { state.withLock { $0.saveGate } }
        set { state.withLock { $0.saveGate = newValue } }
    }
    var saveCallCount: Int {
        get { state.withLock { $0.saveCallCount } }
        set { state.withLock { $0.saveCallCount = newValue } }
    }
    var saveCompletionCount: Int {
        get { state.withLock { $0.saveCompletionCount } }
        set { state.withLock { $0.saveCompletionCount = newValue } }
    }
    var probeCallCount: Int {
        get { state.withLock { $0.probeCallCount } }
        set { state.withLock { $0.probeCallCount = newValue } }
    }
    var probeGate: DispatchSemaphore? {
        get { state.withLock { $0.probeGate } }
        set { state.withLock { $0.probeGate = newValue } }
    }
    var operationRecorder: OperationRecorder? {
        get { state.withLock { $0.operationRecorder } }
        set { state.withLock { $0.operationRecorder = newValue } }
    }
    var statusChangeCount: Int {
        get { state.withLock { $0.statusChangeCount } }
        set { state.withLock { $0.statusChangeCount = newValue } }
    }
}

private final class OperationRecorder: Sendable {
    private let valuesState = Mutex<[String]>([])

    var values: [String] { valuesState.withLock { $0 } }

    func record(_ value: String) {
        valuesState.withLock { $0.append(value) }
    }

    func removeAll() {
        valuesState.withLock { $0.removeAll() }
    }
}

private actor RecordingSession: TrackpadSessionControlling {
    private let recorder: OperationRecorder
    private var continuation: AsyncStream<TrackpadSessionEvent>.Continuation?
    private var workerCount = 0
    private(set) var maximumWorkerCount = 0
    private(set) var startedConfigurations: [TrackIsBackConfiguration] = []

    init(recorder: OperationRecorder) {
        self.recorder = recorder
    }

    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        recorder.record("start")
        workerCount += 1
        maximumWorkerCount = max(maximumWorkerCount, workerCount)
        startedConfigurations.append(configuration)
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        self.continuation = continuation
        continuation.yield(.waitingForController("Fake puck"))
        continuation.yield(.controllerConnected)
        continuation.yield(.outputArmed)
        return stream
    }

    func stop() async {
        recorder.record("stop")
        continuation?.finish()
        continuation = nil
        workerCount = 0
    }
}

private final class ManualSleeper: Sendable {
    private struct State: ~Copyable {
        var pendingWakes = 0
        var nextID: UInt64 = 0
        var waiters: [(id: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []
    }

    private let state = Mutex(State())

    func sleep() async throws {
        try Task.checkCancellation()
        let id: UInt64 = state.withLock { state in
            state.nextID &+= 1
            return state.nextID
        }
        let woken = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let immediate: Bool? = state.withLock { state in
                    if Task.isCancelled { return false }
                    if state.pendingWakes > 0 {
                        state.pendingWakes -= 1
                        return true
                    }
                    state.waiters.append((id, continuation))
                    return nil
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        } onCancel: {
            let cancelled: CheckedContinuation<Bool, Never>? = state.withLock { state in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else {
                    return nil
                }
                return state.waiters.remove(at: index).continuation
            }
            cancelled?.resume(returning: false)
        }
        guard woken else { throw CancellationError() }
        try Task.checkCancellation()
    }

    func wake() {
        let woken: CheckedContinuation<Bool, Never>? = state.withLock { state in
            guard !state.waiters.isEmpty else {
                state.pendingWakes = 1
                return nil
            }
            return state.waiters.removeFirst().continuation
        }
        woken?.resume(returning: true)
    }
}
