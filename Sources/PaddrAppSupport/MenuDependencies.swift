import AppKit
import Foundation
import TrackIsBackCore

public struct MenuDependencies: Sendable {
    public var session: any TrackpadSessionControlling
    public var loadConfiguration: @Sendable () throws -> TrackIsBackConfiguration
    public var saveConfiguration: @Sendable (TrackIsBackConfiguration) throws -> Void
    public var probeController: @Sendable () -> String?
    public var inputMonitoringStatus: @Sendable () -> InputMonitoringStatus
    public var requestInputMonitoring: @Sendable () -> Bool
    public var accessibilityTrusted: @Sendable (_ prompt: Bool) -> Bool
    public var openPrivacySettings: @MainActor @Sendable (_ anchor: String) -> Void
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        session: any TrackpadSessionControlling,
        loadConfiguration: @escaping @Sendable () throws -> TrackIsBackConfiguration,
        saveConfiguration: @escaping @Sendable (TrackIsBackConfiguration) throws -> Void,
        probeController: @escaping @Sendable () -> String?,
        inputMonitoringStatus: @escaping @Sendable () -> InputMonitoringStatus,
        requestInputMonitoring: @escaping @Sendable () -> Bool,
        accessibilityTrusted: @escaping @Sendable (_ prompt: Bool) -> Bool,
        openPrivacySettings: @escaping @MainActor @Sendable (_ anchor: String) -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.session = session
        self.loadConfiguration = loadConfiguration
        self.saveConfiguration = saveConfiguration
        self.probeController = probeController
        self.inputMonitoringStatus = inputMonitoringStatus
        self.requestInputMonitoring = requestInputMonitoring
        self.accessibilityTrusted = accessibilityTrusted
        self.openPrivacySettings = openPrivacySettings
        self.sleep = sleep
    }

    public static let live = MenuDependencies(
        session: TrackpadSession(),
        loadConfiguration: { try ConfigurationStore.load() },
        saveConfiguration: { try ConfigurationStore.save($0) },
        probeController: { TritonHIDDevice.probe()?.description },
        inputMonitoringStatus: {
            InputMonitoringStatus(rawValue: TritonHIDDevice.inputMonitoringStatus()) ?? .unknown
        },
        requestInputMonitoring: TritonHIDDevice.requestInputMonitoring,
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
