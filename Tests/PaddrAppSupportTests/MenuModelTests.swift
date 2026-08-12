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

    func testInitializationFailurePreservesNewerValidationFailureStatus() async {
        let state = readyState(receiver: nil)
        state.loadFailure = "Unreadable configuration"
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.configuration.left.sensitivity = 21
        model.saveAndApply()
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected the newer validation failure")
        }

        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration.left.sensitivity, 21)
        XCTAssertEqual(model.savedConfiguration, .default)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.needsInitialSave)
        guard case .failure(.configurationInvalid) = model.status else {
            return XCTFail("Expected the newer validation failure to remain published")
        }
    }

    func testInitializationFailureDoesNotReplaceTerminationStatus() async {
        let state = readyState(receiver: nil)
        state.loadFailure = "Unreadable configuration"
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.isEnabled = true
        var didComplete = false
        XCTAssertTrue(model.stopForTermination { didComplete = true })
        XCTAssertEqual(model.status, .releasingOutputs)

        loadGate.signal()
        await waitUntil(model: model) { didComplete }

        XCTAssertEqual(model.savedConfiguration, .default)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertTrue(model.needsInitialSave)
        XCTAssertEqual(model.status, .releasingOutputs)
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

    func testEditAndEnableBeforeInitializationPreservesAndActivatesNewerDraft() async {
        let state = readyState(receiver: "Fake")
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))

        model.configuration.left.sensitivity = 7
        model.isEnabled = true
        loadGate.signal()
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
        XCTAssertEqual(model.configuration.left.sensitivity, 7)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 7)
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 7)
        XCTAssertEqual(startedSensitivity, 7)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testDefaultsDuringInitializationPreservesDeliberateDefaultDraft() async {
        let state = readyState(receiver: nil)
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.configuration.left.sensitivity = 7
        model.restoreDefaults()
        loadGate.signal()
        await waitUntil(model: model) { model.isInitialized }

        XCTAssertEqual(model.configuration, .default)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 4)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .defaultsRestored)
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
        XCTAssertTrue(model.hasSystemAccess)

        model.isEnabled = true
        for _ in 0..<1_000 {
            if model.isRunning || !model.isEnabled { break }
            await Task.yield()
        }

        let startCount = await session.startCount
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(startCount, 1)
        XCTAssertTrue(model.isRunning)
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

        XCTAssertEqual(model.receiverDescription, "Fake receiver")
        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)

        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }

        XCTAssertFalse(model.controllerConnected)
        XCTAssertFalse(model.isRunning)
        XCTAssertNotEqual(model.status, .active)
    }

    func testControllerPresenceAndNeutralArmingAreDistinctStatusTransitions() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }

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

    func testControllerLossKeepsReceiverStreamAndWaitsForFreshEvidence() async {
        let state = readyState(receiver: "Fake receiver")
        let session = ManualEventSession()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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

    func testReconnectStartsSessionAndBecomesActive() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
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
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
        )
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }
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

    func testEnableSavesDraftBeforeStarting() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 7

        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 7)
        XCTAssertEqual(startedSensitivity, 7)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEnableSavePersistsNewerDraftBeforeStarting() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.isEnabled = true
        await waitUntil { state.saveCallCount == 1 }
        model.configuration.left.sensitivity = 5
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
        XCTAssertEqual(state.saveCallCount, 2)
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 5)
        XCTAssertEqual(model.savedConfiguration.left.sensitivity, 5)
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertEqual(startedSensitivity, 5)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEnableDuringOverlappingSaveCarriesCommitIntentToReplacementLifecycle() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3
        let saveGate = DispatchSemaphore(value: 0)
        state.saveGate = saveGate

        model.saveAndApply()
        await waitUntil { state.saveCallCount == 1 }
        model.isEnabled = true
        model.configuration.left.sensitivity = 5
        state.saveGate = nil
        saveGate.signal()
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
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
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 0)
        XCTAssertFalse(model.isRunning)
    }

    func testInvalidDraftPreventsSaveAndStart() async {
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 21

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        let startCount = await session.startCount
        XCTAssertNil(state.savedConfiguration)
        XCTAssertEqual(startCount, 0)
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
        model.configuration.left.sensitivity = 6

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        let startCount = await session.startCount
        XCTAssertEqual(startCount, 0)
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
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed], keepsStreamOpen: true)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
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
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.isEnabled = false
        state.receiver = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }

        let startCount = await session.startCount
        XCTAssertEqual(startCount, 0)
        XCTAssertFalse(model.isRunning)
    }

    func testDisconnectedEnableSavesThenReconnectsWithSavedSnapshot() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed])
        let model = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
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
        let state = readyState(receiver: "Fake")
        let session = ScriptedSession(events: [.controllerConnected, .outputArmed], keepsStreamOpen: true)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
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
        let state = readyState(receiver: "Fake")
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
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
        let state = readyState(receiver: "Fake")
        let session = GatedSession(blockedStops: [1])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
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
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.isEnabled = false
        await session.waitForStop(2)
        var didReply = false
        XCTAssertTrue(model.stopForTermination { didReply = true })
        await session.waitForStop(3)
        XCTAssertFalse(didReply)

        await session.releaseStop(2)
        await waitUntil(model: model) { didReply }
        let stopCount = await session.stopCount
        XCTAssertEqual(stopCount, 3)
    }

    func testTerminationCancelsPendingReconnect() async {
        let state = readyState(receiver: nil)
        let sleeper = ManualSleeper()
        let session = GatedSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
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
        let state = readyState(receiver: "Fake")
        let session = GatedSession(blockedStops: [2])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }
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
        await session.waitForStop(2)
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

    func testConfigurationLoadFailureCanSaveRecoveryDefaults() async {
        let state = readyState(receiver: nil)
        state.loadFailure = "Saved sensitivity is outside the supported range."
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.saveAndApply()
        await waitUntil(model: model) { model.status == .configurationSaved }

        XCTAssertEqual(state.savedConfiguration, .default)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertFalse(model.needsInitialSave)
        XCTAssertEqual(model.status, .configurationSaved)
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
        sleeper: ManualSleeper? = nil
    ) -> MenuDependencies {
        MenuDependencies(
            session: session,
            loadConfiguration: {
                state.loadGate?.wait()
                state.loadRanOnMainThread = Thread.isMainThread
                if let failure = state.loadFailure {
                    throw TrackIsBackError.configuration(failure)
                }
                return state.loadedConfiguration
            },
            saveConfiguration: {
                state.saveCallCount += 1
                state.saveGate?.wait()
                if let failure = state.saveFailure {
                    throw TrackIsBackError.configuration(failure)
                }
                state.savedConfiguration = $0
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
        observeOnly: Bool
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
        observeOnly: Bool
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
        observeOnly: Bool
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
        var savedConfiguration: TrackIsBackConfiguration?
        var receiver: String?
        var openedPrivacySettingsAnchors: [String] = []
        var accessibilityGranted = false
        var accessibilityPromptValues: [Bool] = []
        var loadFailure: String?
        var loadGate: DispatchSemaphore?
        var loadRanOnMainThread: Bool?
        var saveFailure: String?
        var saveGate: DispatchSemaphore?
        var saveCallCount = 0
        var probeCallCount = 0
        var probeGate: DispatchSemaphore?
        var statusChangeCount = 0
    }
    private let state = Mutex(State())

    var loadedConfiguration: TrackIsBackConfiguration {
        get { state.withLock { $0.loadedConfiguration } }
        set { state.withLock { $0.loadedConfiguration = newValue } }
    }
    var savedConfiguration: TrackIsBackConfiguration? {
        get { state.withLock { $0.savedConfiguration } }
        set { state.withLock { $0.savedConfiguration = newValue } }
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
    var probeCallCount: Int {
        get { state.withLock { $0.probeCallCount } }
        set { state.withLock { $0.probeCallCount = newValue } }
    }
    var probeGate: DispatchSemaphore? {
        get { state.withLock { $0.probeGate } }
        set { state.withLock { $0.probeGate = newValue } }
    }
    var statusChangeCount: Int {
        get { state.withLock { $0.statusChangeCount } }
        set { state.withLock { $0.statusChangeCount = newValue } }
    }
}

private final class ManualSleeper: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func sleep() async throws {
        var iterator = stream.makeAsyncIterator()
        guard await iterator.next() != nil else { throw CancellationError() }
        try Task.checkCancellation()
    }

    func wake() {
        continuation.yield(())
    }
}
