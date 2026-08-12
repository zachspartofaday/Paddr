import Foundation
import Synchronization
import XCTest
@testable import PaddrAppSupport
import TrackIsBackCore

@MainActor
final class MenuDependencyTests: XCTestCase {
    func testConfigurationAndControllerDependenciesRunOffMainActor() async throws {
        let state = DependencyExecutionState()
        let storedConfiguration: TrackIsBackConfiguration = {
            var configuration = TrackIsBackConfiguration.default
            configuration.left.sensitivity = 4
            return configuration
        }()
        let dependencies = MenuDependencies(
            session: InertSession(),
            loadConfiguration: {
                state.loadRanOnMainThread = Thread.isMainThread
                return storedConfiguration
            },
            saveConfiguration: { configuration in
                state.saveRanOnMainThread = Thread.isMainThread
                state.savedConfiguration = configuration
            },
            probeController: {
                state.probeRanOnMainThread = Thread.isMainThread
                return "Fake puck"
            },
            accessibilityTrusted: { _ in true },
            openPrivacySettings: { _ in },
            sleep: { _ in }
        )

        let loadedConfiguration = try await dependencies.loadConfiguration()
        try await dependencies.saveConfiguration(loadedConfiguration)
        let controllerDescription = await dependencies.probeController()

        XCTAssertEqual(loadedConfiguration.left.sensitivity, 4)
        XCTAssertEqual(state.savedConfiguration, loadedConfiguration)
        XCTAssertEqual(controllerDescription, "Fake puck")
        XCTAssertEqual(state.loadRanOnMainThread, false)
        XCTAssertEqual(state.saveRanOnMainThread, false)
        XCTAssertEqual(state.probeRanOnMainThread, false)
    }
}

private actor InertSession: TrackpadSessionControlling {
    func start(
        configuration: TrackIsBackConfiguration,
        observeOnly: Bool
    ) async -> AsyncStream<TrackpadSessionEvent> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}
}

private final class DependencyExecutionState: Sendable {
    private struct State: ~Copyable {
        var savedConfiguration: TrackIsBackConfiguration?
        var loadRanOnMainThread: Bool?
        var saveRanOnMainThread: Bool?
        var probeRanOnMainThread: Bool?
    }

    private let state = Mutex(State())

    var savedConfiguration: TrackIsBackConfiguration? {
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
