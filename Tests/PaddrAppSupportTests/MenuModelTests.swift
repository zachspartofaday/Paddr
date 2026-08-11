import Synchronization
import XCTest
@testable import PaddrAppSupport
import TrackIsBackCore

@MainActor
final class MenuModelTests: XCTestCase {
    func testMissingPermissionTurnsOutputBackOffWithFailure() async {
        let state = ModelDependencyState()
        state.inputGranted = false
        state.accessibilityGranted = true
        state.controller = "Fake"
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.isEnabled = true
        await waitUntil(model: model) { !model.isEnabled }

        XCTAssertFalse(model.isRunning)
        guard case .failure = model.status else { return XCTFail("Expected a permission failure") }
    }

    func testDisconnectedEnableStaysOnAndWaits() async {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

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

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController && model.reportCount == 4 }

        XCTAssertTrue(model.isEnabled)
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.controllerDescription)
    }

    func testSaveAndApplyPersistsValidatedConfiguration() {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        model.configuration.left.sensitivity = 3.4

        model.saveAndApply()

        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 3.4)
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .configurationSaved)
    }

    func testAlreadyGrantedPermissionRequestsReturnToOperationalStatus() {
        let state = readyState(controller: nil)
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.requestInputMonitoring()
        XCTAssertEqual(model.status, .off)

        model.requestAccessibility()
        XCTAssertEqual(model.status, .off)
    }

    func testDelayedPermissionRefreshClearsRequestingStatuses() async {
        let state = ModelDependencyState()
        let sleeper = ManualSleeper()
        let model = PaddrMenuModel(dependencies: dependencies(state: state, sleeper: sleeper))

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
        model.configuration.left.sensitivity = 7

        model.isEnabled = true
        await waitUntil(model: model) { await session.startCount == 1 }

        let startedSensitivity = await session.startedConfigurations.first?.left.sensitivity
        XCTAssertEqual(state.savedConfiguration?.left.sensitivity, 7)
        XCTAssertEqual(startedSensitivity, 7)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testInvalidDraftPreventsSaveAndStart() async {
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [])
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
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

    func testSaveAndApplyFailurePreservesDraft() {
        let state = readyState(controller: nil)
        state.saveFailure = "disk full"
        let model = PaddrMenuModel(dependencies: dependencies(state: state))
        model.configuration.left.sensitivity = 6

        model.saveAndApply()

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
        model.configuration.right.sensitivity = 8

        model.isEnabled = true
        await waitUntil(model: model) { model.status == .waitingForController }
        state.loadedConfiguration = try! XCTUnwrap(state.savedConfiguration)

        let relaunched = PaddrMenuModel(dependencies: dependencies(state: state))
        XCTAssertEqual(relaunched.configuration.right.sensitivity, 8)
        XCTAssertFalse(relaunched.hasUnsavedChanges)
    }

    func testTerminationAwaitsSessionStop() async {
        let state = readyState(controller: "Fake")
        let session = ScriptedSession(events: [.connected("Fake puck")], keepsStreamOpen: true)
        let model = PaddrMenuModel(dependencies: dependencies(state: state, session: session))
        model.isEnabled = true
        await waitUntil(model: model) { model.isRunning }

        var didComplete = false
        XCTAssertTrue(model.stopForTermination { didComplete = true })
        await waitUntil(model: model) { didComplete }

        let stopCount = await session.stopCount
        XCTAssertGreaterThanOrEqual(stopCount, 2)
        XCTAssertEqual(model.status, .releasingOutputs)
    }

    func testRestoreDefaultsMarksConfigurationUnsaved() {
        let state = readyState(controller: nil)
        var custom = TrackIsBackConfiguration.default
        custom.left.sensitivity = 4
        state.loadedConfiguration = custom
        let model = PaddrMenuModel(dependencies: dependencies(state: state))

        model.restoreDefaults()

        XCTAssertEqual(model.configuration, .default)
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(model.status, .defaultsRestored)
    }

    func testConfigurationLoadFailureUsesDefaultsAndSurfacesError() {
        let state = readyState(controller: nil)
        var environment = dependencies(state: state)
        environment.loadConfiguration = {
            throw TrackIsBackError.configuration("Saved sensitivity is outside the supported range.")
        }

        let model = PaddrMenuModel(dependencies: environment)

        XCTAssertEqual(model.configuration, .default)
        guard case let .failure(.configurationLoad(diagnostic)) = model.status else {
            return XCTFail("Expected a typed load failure")
        }
        XCTAssertEqual(diagnostic, "Saved sensitivity is outside the supported range.")
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
            loadConfiguration: { state.loadedConfiguration },
            saveConfiguration: {
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

private final class ModelDependencyState: Sendable {
    private struct State: ~Copyable {
        var loadedConfiguration = TrackIsBackConfiguration.default
        var savedConfiguration: TrackIsBackConfiguration?
        var controller: String?
        var inputGranted = false
        var accessibilityGranted = false
        var saveFailure: String?
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
    var saveFailure: String? {
        get { state.withLock { $0.saveFailure } }
        set { state.withLock { $0.saveFailure = newValue } }
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
