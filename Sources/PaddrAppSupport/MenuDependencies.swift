import AppKit
import Foundation
import TrackIsBackCore

public struct MenuDependencies: Sendable {
    public var session: any TrackpadSessionControlling
    private let background: BackgroundMenuDependencies
    public var accessibilityTrusted: @Sendable (_ prompt: Bool) -> Bool
    public var openPrivacySettings: @MainActor @Sendable (_ anchor: String) -> Void
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        session: any TrackpadSessionControlling,
        loadConfiguration: @escaping @Sendable () throws -> TrackIsBackConfiguration,
        saveConfiguration: @escaping @Sendable (TrackIsBackConfiguration) throws -> Void,
        probeReceiver: @escaping @Sendable () -> String?,
        accessibilityTrusted: @escaping @Sendable (_ prompt: Bool) -> Bool,
        openPrivacySettings: @escaping @MainActor @Sendable (_ anchor: String) -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.session = session
        background = BackgroundMenuDependencies(
            loadConfiguration: loadConfiguration,
            saveConfiguration: saveConfiguration,
            probeReceiver: probeReceiver
        )
        self.accessibilityTrusted = accessibilityTrusted
        self.openPrivacySettings = openPrivacySettings
        self.sleep = sleep
    }

    func loadConfiguration() async throws -> TrackIsBackConfiguration {
        try await background.loadConfiguration()
    }

    func saveConfiguration(_ configuration: TrackIsBackConfiguration) async throws {
        try await background.saveConfiguration(configuration)
    }

    func probeReceiver() async -> String? {
        await background.probeReceiver()
    }

    public static let live = MenuDependencies(
        session: TrackpadSession(),
        loadConfiguration: { try ConfigurationStore.load() },
        saveConfiguration: { try ConfigurationStore.save($0) },
        probeReceiver: { TritonHIDDevice.probe()?.description },
        accessibilityTrusted: Permissions.accessibilityTrusted,
        openPrivacySettings: { anchor in
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
            ) else { return }
            NSWorkspace.shared.open(url)
        },
        sleep: { try await Task.sleep(for: $0) }
    )
}

private actor BackgroundMenuDependencies {
    private let load: @Sendable () throws -> TrackIsBackConfiguration
    private let save: @Sendable (TrackIsBackConfiguration) throws -> Void
    private let probe: @Sendable () -> String?

    init(
        loadConfiguration: @escaping @Sendable () throws -> TrackIsBackConfiguration,
        saveConfiguration: @escaping @Sendable (TrackIsBackConfiguration) throws -> Void,
        probeReceiver: @escaping @Sendable () -> String?
    ) {
        load = loadConfiguration
        save = saveConfiguration
        probe = probeReceiver
    }

    func loadConfiguration() throws -> TrackIsBackConfiguration {
        try load()
    }

    func saveConfiguration(_ configuration: TrackIsBackConfiguration) throws {
        try save(configuration)
    }

    func probeReceiver() -> String? {
        probe()
    }
}
