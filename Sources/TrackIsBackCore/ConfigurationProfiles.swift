import Foundation

public struct ConfigurationProfileID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public static let `default` = ConfigurationProfileID(
        rawValue: "00000000-0000-0000-0000-000000000001"
    )

    public init(rawValue: String) {
        if let uuid = UUID(uuidString: rawValue) {
            self.rawValue = uuid.uuidString.lowercased()
        } else {
            self.rawValue = rawValue
        }
    }

    public static func make() -> ConfigurationProfileID {
        ConfigurationProfileID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ConfigurationProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: ConfigurationProfileID
    public var name: String
    public var configuration: TrackIsBackConfiguration

    public static let `default` = ConfigurationProfile(
        id: .default,
        name: "Default",
        configuration: .default
    )

    public init(
        id: ConfigurationProfileID,
        name: String,
        configuration: TrackIsBackConfiguration
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

public struct ConfigurationProfileDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var activeProfileID: ConfigurationProfileID
    public private(set) var userProfiles: [ConfigurationProfile]

    public static let `default` = ConfigurationProfileDocument(
        activeProfileID: .default,
        userProfiles: []
    )

    public init(
        activeProfileID: ConfigurationProfileID,
        userProfiles: [ConfigurationProfile],
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.activeProfileID = activeProfileID
        self.userProfiles = userProfiles
    }

    public var profiles: [ConfigurationProfile] {
        [.default] + userProfiles
    }

    public var activeProfile: ConfigurationProfile? {
        profile(id: activeProfileID)
    }

    public func profile(id: ConfigurationProfileID) -> ConfigurationProfile? {
        if id == .default { return .default }
        return userProfiles.first { $0.id == id }
    }

    public func profile(matching identifierOrName: String) -> ConfigurationProfile? {
        if UUID(uuidString: identifierOrName) != nil {
            let identifier = ConfigurationProfileID(rawValue: identifierOrName)
            if let exactID = profile(id: identifier) { return exactID }
        }
        let key = Self.nameKey(identifierOrName)
        return profiles.first { Self.nameKey($0.name) == key }
    }

    public func validated(repairingMissingActiveProfile: Bool = false) throws -> ConfigurationProfileDocument {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TrackIsBackError.configuration(
                "Unsupported profile document schema version \(schemaVersion)."
            )
        }

        var seenIDs: Set<ConfigurationProfileID> = [.default]
        var seenNames: Set<String> = [Self.nameKey(ConfigurationProfile.default.name)]
        var validatedProfiles: [ConfigurationProfile] = []
        validatedProfiles.reserveCapacity(userProfiles.count)

        for profile in userProfiles {
            guard profile.id != .default, UUID(uuidString: profile.id.rawValue) != nil else {
                throw TrackIsBackError.configuration(
                    "User profile \(profile.name) has an invalid stable ID."
                )
            }
            guard seenIDs.insert(profile.id).inserted else {
                throw TrackIsBackError.configuration("Profile IDs must be unique.")
            }
            let name = try Self.validatedName(profile.name)
            guard seenNames.insert(Self.nameKey(name)).inserted else {
                throw TrackIsBackError.configuration("Profile names must be unique, ignoring case.")
            }
            validatedProfiles.append(
                ConfigurationProfile(
                    id: profile.id,
                    name: name,
                    configuration: try profile.configuration.validated()
                )
            )
        }

        var copy = ConfigurationProfileDocument(
            activeProfileID: activeProfileID,
            userProfiles: validatedProfiles,
            schemaVersion: schemaVersion
        )
        guard copy.profile(id: copy.activeProfileID) != nil else {
            if repairingMissingActiveProfile {
                copy.activeProfileID = .default
                return copy
            }
            throw TrackIsBackError.configuration(
                "The active profile ID \(activeProfileID.rawValue) does not exist."
            )
        }
        return copy
    }

    @discardableResult
    public mutating func createProfile(
        named proposedName: String,
        configuration: TrackIsBackConfiguration = .default,
        id: ConfigurationProfileID = .make()
    ) throws -> ConfigurationProfile {
        let name = try availableName(proposedName)
        guard id != .default, UUID(uuidString: id.rawValue) != nil,
              profile(id: id) == nil else {
            throw TrackIsBackError.configuration("The new profile ID is invalid or already exists.")
        }
        let profile = ConfigurationProfile(
            id: id,
            name: name,
            configuration: try configuration.validated()
        )
        userProfiles.append(profile)
        return profile
    }

    @discardableResult
    public mutating func duplicateProfile(
        id sourceID: ConfigurationProfileID,
        newID: ConfigurationProfileID = .make()
    ) throws -> ConfigurationProfile {
        guard let source = profile(id: sourceID) else {
            throw TrackIsBackError.configuration("The profile to duplicate no longer exists.")
        }
        let baseName = "\(source.name) Copy"
        var candidate = baseName
        var suffix = 2
        while containsName(candidate) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        return try createProfile(named: candidate, configuration: source.configuration, id: newID)
    }

    public mutating func renameProfile(id: ConfigurationProfileID, to proposedName: String) throws {
        guard id != .default else {
            throw TrackIsBackError.configuration("The Default profile cannot be renamed.")
        }
        guard let index = userProfiles.firstIndex(where: { $0.id == id }) else {
            throw TrackIsBackError.configuration("The profile to rename no longer exists.")
        }
        let name = try Self.validatedName(proposedName)
        let key = Self.nameKey(name)
        guard !profiles.contains(where: { $0.id != id && Self.nameKey($0.name) == key }) else {
            throw TrackIsBackError.configuration("A profile named \(name) already exists.")
        }
        userProfiles[index].name = name
    }

    public mutating func replaceConfiguration(
        for id: ConfigurationProfileID,
        with configuration: TrackIsBackConfiguration
    ) throws {
        guard id != .default else {
            guard configuration == .default else {
                throw TrackIsBackError.configuration(
                    "The Default profile is built in. Duplicate it before customizing."
                )
            }
            return
        }
        guard let index = userProfiles.firstIndex(where: { $0.id == id }) else {
            throw TrackIsBackError.configuration("The active profile no longer exists.")
        }
        userProfiles[index].configuration = try configuration.validated()
    }

    public mutating func activateProfile(id: ConfigurationProfileID) throws {
        guard profile(id: id) != nil else {
            throw TrackIsBackError.configuration("The profile to activate no longer exists.")
        }
        activeProfileID = id
    }

    public mutating func deleteProfile(id: ConfigurationProfileID) throws {
        guard id != .default else {
            throw TrackIsBackError.configuration("The Default profile cannot be deleted.")
        }
        guard let index = userProfiles.firstIndex(where: { $0.id == id }) else {
            throw TrackIsBackError.configuration("The profile to delete no longer exists.")
        }
        if activeProfileID == id { activeProfileID = .default }
        userProfiles.remove(at: index)
    }

    private func availableName(_ proposedName: String) throws -> String {
        let name = try Self.validatedName(proposedName)
        guard !containsName(name) else {
            throw TrackIsBackError.configuration("A profile named \(name) already exists.")
        }
        return name
    }

    private func containsName(_ name: String) -> Bool {
        let key = Self.nameKey(name)
        return profiles.contains { Self.nameKey($0.name) == key }
    }

    private static func validatedName(_ proposedName: String) throws -> String {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw TrackIsBackError.configuration("Profile names cannot be empty.")
        }
        return name
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

public struct ConfigurationProfileLoadResult: Equatable, Sendable {
    public var document: ConfigurationProfileDocument
    public var diagnostic: String?

    public init(document: ConfigurationProfileDocument, diagnostic: String? = nil) {
        self.document = document
        self.diagnostic = diagnostic
    }
}
