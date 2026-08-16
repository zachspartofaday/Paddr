import Foundation
import Synchronization
import XCTest
@testable import PaddrAppSupport
import PaddrCore

@MainActor
final class MenuDependencyTests: XCTestCase {
    func testConfigurationAndReceiverDependenciesRunOffMainActor() async throws {
        let state = DependencyExecutionState()
        let storedConfiguration: PaddrConfiguration = {
            var configuration = PaddrConfiguration.default
            configuration.left.sensitivity = 4
            return configuration
        }()
        var mutableDocument = ConfigurationProfileDocument.default
        let profile = try mutableDocument.createProfile(named: "Stored", configuration: storedConfiguration)
        mutableDocument.activeProfileID = profile.id
        let storedDocument = mutableDocument
        let dependencies = MenuDependencies(
            session: InertSession(),
            loadProfiles: {
                state.loadRanOnMainThread = Thread.isMainThread
                return ConfigurationProfileLoadResult(document: storedDocument)
            },
            saveProfiles: { document in
                state.saveRanOnMainThread = Thread.isMainThread
                state.savedConfiguration = document.activeProfile?.configuration
            },
            probeReceiver: {
                state.probeRanOnMainThread = Thread.isMainThread
                return "Fake puck"
            },
            accessibilityTrusted: { _ in true },
            openPrivacySettings: { _ in },
            sleep: { _ in }
        )

        let loadedDocument = try await dependencies.loadProfiles().document
        try await dependencies.saveProfiles(loadedDocument)
        let receiverDescription = await dependencies.probeReceiver()

        XCTAssertEqual(loadedDocument.activeProfile?.configuration.left.sensitivity, 4)
        XCTAssertEqual(state.savedConfiguration, loadedDocument.activeProfile?.configuration)
        XCTAssertEqual(receiverDescription, "Fake puck")
        XCTAssertEqual(state.loadRanOnMainThread, false)
        XCTAssertEqual(state.saveRanOnMainThread, false)
        XCTAssertEqual(state.probeRanOnMainThread, false)
    }
}

private actor InertSession: TrackpadSessionControlling {
    func start(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        AsyncStream { $0.finish() }
    }

    @discardableResult
    func stop() async -> TrackpadSessionStopOutcome { .clean }
}

private final class DependencyExecutionState: Sendable {
    private struct State: ~Copyable {
        var savedConfiguration: PaddrConfiguration?
        var loadRanOnMainThread: Bool?
        var saveRanOnMainThread: Bool?
        var probeRanOnMainThread: Bool?
    }

    private let state = Mutex(State())

    var savedConfiguration: PaddrConfiguration? {
        get { state.withLock { $0.savedConfiguration } }
        set { state.withLock { $0.savedConfiguration = newValue } }
    }

    var loadRanOnMainThread: Bool? {
        get { state.withLock { $0.loadRanOnMainThread } }
        set { state.withLock { $0.loadRanOnMainThread = newValue } }
    }

    var saveRanOnMainThread: Bool? {
        get { state.withLock { $0.saveRanOnMainThread } }
        set { state.withLock { $0.saveRanOnMainThread = newValue } }
    }

    var probeRanOnMainThread: Bool? {
        get { state.withLock { $0.probeRanOnMainThread } }
        set { state.withLock { $0.probeRanOnMainThread = newValue } }
    }
}
