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
        loadProfiles: @escaping @Sendable () throws -> ConfigurationProfileLoadResult,
        saveProfiles: @escaping @Sendable (ConfigurationProfileDocument) throws -> Void,
        probeReceiver: @escaping @Sendable () -> String?,
        accessibilityTrusted: @escaping @Sendable (_ prompt: Bool) -> Bool,
        openPrivacySettings: @escaping @MainActor @Sendable (_ anchor: String) -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.session = session
        background = BackgroundMenuDependencies(
            loadProfiles: loadProfiles,
            saveProfiles: saveProfiles,
            probeReceiver: probeReceiver
        )
        self.accessibilityTrusted = accessibilityTrusted
        self.openPrivacySettings = openPrivacySettings
        self.sleep = sleep
    }

    func loadProfiles() async throws -> ConfigurationProfileLoadResult {
        try await background.loadProfiles()
    }

    func saveProfiles(_ document: ConfigurationProfileDocument) async throws {
        try await background.saveProfiles(document)
    }

    func probeReceiver() async -> String? {
        await background.probeReceiver()
    }

    public static let live = MenuDependencies(
        session: TrackpadSession(),
        loadProfiles: { try ConfigurationProfileStore.load() },
        saveProfiles: { try ConfigurationProfileStore.save($0) },
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
    private let load: @Sendable () throws -> ConfigurationProfileLoadResult
    private let save: @Sendable (ConfigurationProfileDocument) throws -> Void
    private let probe: @Sendable () -> String?

    init(
        loadProfiles: @escaping @Sendable () throws -> ConfigurationProfileLoadResult,
        saveProfiles: @escaping @Sendable (ConfigurationProfileDocument) throws -> Void,
        probeReceiver: @escaping @Sendable () -> String?
    ) {
        load = loadProfiles
        save = saveProfiles
        probe = probeReceiver
    }

    func loadProfiles() throws -> ConfigurationProfileLoadResult {
        try load()
    }

    func saveProfiles(_ document: ConfigurationProfileDocument) throws {
        try save(document)
    }

    func probeReceiver() -> String? {
        probe()
    }
}
