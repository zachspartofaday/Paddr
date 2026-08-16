import AppKit
import Foundation
import PaddrCore

public struct MenuDependencies: Sendable {
    public var session: any TrackpadSessionControlling
    private let background: BackgroundMenuDependencies
    public var accessibilityTrusted: @Sendable (_ prompt: Bool) -> Bool
    public var inputMonitoringAccess: @Sendable (_ requestIfUndetermined: Bool) -> InputMonitoringAccess
    public var openPrivacySettings: @MainActor @Sendable (_ anchor: String) -> Void
    public var sleep: @Sendable (Duration) async throws -> Void
    public var reconnectDelay: @Sendable (Duration) async throws -> Void

    public init(
        session: any TrackpadSessionControlling,
        loadProfiles: @escaping @Sendable () throws -> ConfigurationProfileLoadResult,
        saveProfiles: @escaping @Sendable (ConfigurationProfileDocument) throws -> Void,
        probeReceiver: @escaping @Sendable () -> String?,
        accessibilityTrusted: @escaping @Sendable (_ prompt: Bool) -> Bool,
        inputMonitoringAccess: (@Sendable (_ requestIfUndetermined: Bool) -> InputMonitoringAccess)? = nil,
        openPrivacySettings: @escaping @MainActor @Sendable (_ anchor: String) -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        reconnectDelay: (@Sendable (Duration) async throws -> Void)? = nil
    ) {
        self.session = session
        background = BackgroundMenuDependencies(
            loadProfiles: loadProfiles,
            saveProfiles: saveProfiles,
            probeReceiver: probeReceiver
        )
        self.accessibilityTrusted = accessibilityTrusted
        self.inputMonitoringAccess = inputMonitoringAccess ?? { _ in .granted }
        self.openPrivacySettings = openPrivacySettings
        self.sleep = sleep
        self.reconnectDelay = reconnectDelay ?? sleep
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
        inputMonitoringAccess: Permissions.inputMonitoringAccess,
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
