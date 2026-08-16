import Foundation

public enum ConfigurationProfileStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/Paddr/config.json")
    }

    public static func load(from url: URL? = nil) throws -> ConfigurationProfileLoadResult {
        try load(
            from: url,
            fileManager: .default,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            writeAtomically: atomicWrite
        )
    }

    public static func save(
        _ document: ConfigurationProfileDocument,
        to url: URL? = nil
    ) throws {
        try save(
            document,
            to: url ?? defaultURL,
            fileManager: .default,
            writeAtomically: atomicWrite
        )
    }

    public static func encoded(_ document: ConfigurationProfileDocument) throws -> Data {
        let validated = try document.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(validated) + Data("\n".utf8)
    }

    static func load(
        from url: URL?,
        fileManager: FileManager,
        homeDirectory: URL,
        writeAtomically: (_ data: Data, _ destination: URL) throws -> Void
    ) throws -> ConfigurationProfileLoadResult {
        let destination = url ?? homeDirectory.appendingPathComponent(".config/Paddr/config.json")
        let candidate = url ?? ConfigurationStore.defaultCandidateURL(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )
        guard fileManager.fileExists(atPath: candidate.path) else {
            return ConfigurationProfileLoadResult(document: .default)
        }

        let data: Data
        do {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw PaddrError.configuration(
                    "Profile storage path is not a regular file: \(candidate.path)."
                )
            }
            data = try Data(contentsOf: candidate)
        } catch let error as PaddrError {
            throw error
        } catch {
            throw PaddrError.configuration(
                "Could not read profile storage at \(candidate.path): \(error)"
            )
        }

        do {
            if try isProfileDocument(data) {
                let decoded = try JSONDecoder().decode(ConfigurationProfileDocument.self, from: data)
                let repaired = try decoded.validated(repairingMissingActiveProfile: true)
                let diagnostic: String? = repaired.activeProfileID == decoded.activeProfileID
                    ? nil
                    : "The saved active profile ID \(decoded.activeProfileID.rawValue) was missing. Default is active; user profiles were preserved."
                return ConfigurationProfileLoadResult(document: repaired, diagnostic: diagnostic)
            }

            let legacy = try decodeLegacyConfiguration(data)
            var migrated = ConfigurationProfileDocument.default
            if legacy == PaddrConfiguration.formerCoupledDefault {
                migrated.builtInDefaultCenterTapTrackingMode = .coupled
            } else if legacy != .default {
                let previous = try migrated.createProfile(
                    named: "Previous configuration",
                    configuration: legacy
                )
                migrated.activeProfileID = previous.id
            }
            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try writeAtomically(try encoded(migrated), destination)
            } catch {
                throw PaddrError.configuration(
                    "Could not migrate configuration to profiles at \(destination.path). The original file at \(candidate.path) was preserved: \(error)"
                )
            }
            return ConfigurationProfileLoadResult(document: migrated)
        } catch let error as PaddrError {
            throw error
        } catch {
            throw PaddrError.configuration(
                "Could not load profile storage at \(candidate.path): \(error)"
            )
        }
    }

    static func save(
        _ document: ConfigurationProfileDocument,
        to destination: URL,
        fileManager: FileManager,
        writeAtomically: (_ data: Data, _ destination: URL) throws -> Void
    ) throws {
        do {
            let data = try encoded(document)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try writeAtomically(data, destination)
        } catch let error as PaddrError {
            throw error
        } catch {
            throw PaddrError.configuration(
                "Could not save profiles at \(destination.path): \(error)"
            )
        }
    }

    static func decodeConfiguration(from data: Data) throws -> PaddrConfiguration {
        try decodeConfigurationInput(from: data).configuration
    }

    static func decodeConfigurationInput(
        from data: Data
    ) throws -> (
        configuration: PaddrConfiguration,
        profileDocument: ConfigurationProfileDocument?
    ) {
        if try isProfileDocument(data) {
            let document = try JSONDecoder().decode(ConfigurationProfileDocument.self, from: data)
            let validated = try document.validated()
            guard let active = validated.activeProfile else {
                throw PaddrError.configuration("The active profile does not exist.")
            }
            return (active.configuration, validated)
        }
        return (try decodeLegacyConfiguration(data), nil)
    }

    static func isProfileDocument(_ data: Data) throws -> Bool {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaddrError.configuration("Configuration JSON must contain an object.")
        }
        return object["schemaVersion"] != nil
            || object["activeProfileID"] != nil
            || object["userProfiles"] != nil
    }

    private static func decodeLegacyConfiguration(_ data: Data) throws -> PaddrConfiguration {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["left"] != nil || object["right"] != nil else {
            throw PaddrError.configuration(
                "Configuration JSON is neither a profile document nor a legacy left/right configuration."
            )
        }
        return try JSONDecoder().decode(PaddrConfiguration.self, from: data).validated()
    }

    private static func atomicWrite(_ data: Data, _ destination: URL) throws {
        try data.write(to: destination, options: .atomic)
    }
}
