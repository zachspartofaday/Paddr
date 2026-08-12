import Foundation
import Synchronization
import XCTest
@testable import PaddrAppSupport
import TrackIsBackCore

@MainActor
final class MenuModelTests: XCTestCase {
    func testInitializationLoadsConfigurationOffMainActorBeforePublishingSnapshot() async {
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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

    func testEditAndEnableBeforeInitializationPreservesAndActivatesNewerDraft() async {
        let state = readyState(controller: "Fake")
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let loadGate = DispatchSemaphore(value: 0)
        state.loadGate = loadGate
        let session = ScriptedSession(events: [.connected("Fake puck")])
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
        let state = readyState(controller: nil)
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

    func testMissingPermissionTurnsOutputBackOffWithFailure() async {
        let state = ModelDependencyState()
        state.inputGranted = false
        state.accessibilityGranted = true
        state.controller = "Fake"
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        XCTAssertFalse(model.isRunning)
        guard case .failure = model.status else { return XCTFail("Expected a permission failure") }
    }

    func testDisconnectedEnableStaysOnAndWaits() async {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.controllerConnected)
    }

    func testReconnectStartsSessionAndBecomesActive() async {
        let state = readyState(controller: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.connected("Fake puck")])
        let model = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
        )
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        state.controller = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { model.isRunning }

        XCTAssertTrue(model.isEnabled)
        XCTAssertTrue(model.controllerConnected)
        let startCount = await session.startCount
        XCTAssertEqual(startCount, 1)
    }

    func testDeviceRemovalKeepsToggleOnAndReturnsToWaiting() async {
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [
            .connected("Fake puck"),
            .deviceRemoved(.init(reportCount: 4, actionCount: 2))
        ])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        await waitUntil(model: model) { model.isInitialized }

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController && model.reportCount == 4 }

        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.controllerDescription)
    }

    func testSaveAndApplyPersistsValidatedConfiguration() async {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3.4

        model.saveAndApply()
        await waitUntil(model: model) { model.status == .configurationSaved }

        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3.4)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .configurationSaved)
    }

    func testSaveCompletionPreservesNewerDraft() async {
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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

    func testAlreadyGrantedPermissionRequestsReturnToOperationalStatus() async {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }

        model.requestInputMonitoring()
        XCTAssertEqual(model.status, .off)

        model.requestAccessibility()
        XCTAssertEqual(model.status, .off)
    }

    func testDelayedPermissionRefreshClearsRequestingStatuses() async {
        let state = ModelDependencyState()
        let sleeper = ManualSleeper()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, sleeper: sleeper))
        await waitUntil(model: model) { model.isInitialized }

        model.requestInputMonitoring()
        XCTAssertEqual(model.status, .requestingInputMonitoring)
        state.inputGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }

        model.requestAccessibility()
        XCTAssertEqual(model.status, .requestingAccessibility)
        state.accessibilityGranted = true
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }
    }

    func testEnableSavesDraftBeforeStarting() async {
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [.connected("Fake puck")])
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
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [.connected("Fake puck")])
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
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [.connected("Fake puck")])
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
        let state = readyState(controller: "Fake")
        var stored = TrackIsBackConfiguration.default
        stored.left.sensitivity = 4
        state.loadedConfiguration = stored
        let session = ScriptedSession(events: [.connected("Fake puck")])
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
        let state = readyState(controller: "Fake")
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
        let state = readyState(controller: "Fake")
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
        let state = readyState(controller: nil)
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
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [.connected("Fake puck")], keepsStreamOpen: true)
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
        let state = readyState(controller: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.connected("Fake puck")])
        let model = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
        )
        await waitUntil(model: model) { model.isInitialized }
        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }

        model.isEnabled = false
        state.controller = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { model.status == .off }

        let startCount = await session.startCount
        XCTAssertEqual(startCount, 0)
        XCTAssertFalse(model.isRunning)
    }

    func testDisconnectedEnableSavesThenReconnectsWithSavedSnapshot() async {
        let state = readyState(controller: nil)
        let sleeper = ManualSleeper()
        let session = ScriptedSession(events: [.connected("Fake puck")])
        let model = PaddrMenuModel(
            dependencies: dependencies(state: state, session: session, sleeper: sleeper)
        )
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.left.sensitivity = 3

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3)

        model.configuration.left.sensitivity = 5
        state.controller = "Fake puck"
        sleeper.wake()
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
        XCTAssertEqual(startedSensitivity, 3)
        XCTAssertEqual(model.configuration.left.sensitivity, 5)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testRelaunchLoadsConfigurationSavedByEnable() async {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: model) { model.isInitialized }
        model.configuration.right.sensitivity = 8

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        state.loadedConfiguration = try! XCTUnwrap(state.savedConfiguration)

        let relaunched = PaddrMenuModel(dependencies: dependencies(state: state))
        await waitUntil(model: relaunched) { relaunched.isInitialized }
        XCTAssertEqual(relaunched.configuration.right.sensitivity, 8)
        XCTAssertFalse(relaunched.hasUnsavedChanges)
    }

    func testTerminationAwaitsSessionStop() async {
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [.connected("Fake puck")], keepsStreamOpen: true)
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
        let state = readyState(controller: "Fake")
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
        let state = readyState(controller: "Fake")
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
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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

        state.controller = "Late controller"
        sleeper.wake()
        let startCount = await session.startCount
        let stopCount = await session.stopCount
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(stopCount, 2)
    }

    func testTerminationDuringSaveAndApplyPreventsRestart() async {
        let state = readyState(controller: "Fake")
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
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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
        let state = readyState(controller: nil)
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

    private func readyState(controller: String?) -> ModelDependencyState {
        let state = ModelDependencyState()
        state.inputGranted = true
        state.accessibilityGranted = true
        state.controller = controller
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
            probeController: { state.controller },
            inputMonitoringStatus: { state.inputGranted ? .granted : .denied },
            requestInputMonitoring: { state.inputGranted },
            accessibilityTrusted: { _ in state.accessibilityGranted },
            openPrivacySettings: { _ in },
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
        continuation.yield(.connected("Fake puck"))
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
        var controller: String?
        var inputGranted = false
        var accessibilityGranted = false
        var loadFailure: String?
        var loadGate: DispatchSemaphore?
        var loadRanOnMainThread: Bool?
        var saveFailure: String?
        var saveGate: DispatchSemaphore?
        var saveCallCount = 0
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
    var controller: String? {
        get { state.withLock { $0.controller } }
        set { state.withLock { $0.controller = newValue } }
    }
    var inputGranted: Bool {
        get { state.withLock { $0.inputGranted } }
        set { state.withLock { $0.inputGranted = newValue } }
    }
    var accessibilityGranted: Bool {
        get { state.withLock { $0.accessibilityGranted } }
        set { state.withLock { $0.accessibilityGranted = newValue } }
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
