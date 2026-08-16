import Foundation

public enum ConfigurationStore {
    public static var defaultURL: URL { ConfigurationProfileStore.defaultURL }

    public static func load(from url: URL? = nil) throws -> PaddrConfiguration {
        try load(
            from: url,
            fileManager: .default,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    package static func loadInput(
        from url: URL
    ) throws -> (
        configuration: PaddrConfiguration,
        profileDocument: ConfigurationProfileDocument?
    ) {
        try loadInput(
            from: url,
            fileManager: .default,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func load(
        from url: URL?,
        fileManager: FileManager,
        homeDirectory: URL
    ) throws -> PaddrConfiguration {
        try loadInput(
            from: url,
            fileManager: fileManager,
            homeDirectory: homeDirectory
        ).configuration
    }

    private static func loadInput(
        from url: URL?,
        fileManager: FileManager,
        homeDirectory: URL
    ) throws -> (
        configuration: PaddrConfiguration,
        profileDocument: ConfigurationProfileDocument?
    ) {
        let isExplicitURL = url != nil
        let candidate = url ?? defaultCandidateURL(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )
        guard fileManager.fileExists(atPath: candidate.path) else {
            if isExplicitURL {
                throw PaddrError.configuration(
                    "Configuration file does not exist at \(candidate.path)."
                )
            }
            return (.default, nil)
        }
        do {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw PaddrError.configuration(
                    "Configuration path is not a regular file: \(candidate.path)."
                )
            }
            let data = try Data(contentsOf: candidate)
            return try ConfigurationProfileStore.decodeConfigurationInput(from: data)
        } catch let error as PaddrError {
            throw error
        } catch {
            throw PaddrError.configuration("Could not load configuration at \(candidate.path): \(error)")
        }
    }

    public static func encoded(_ configuration: PaddrConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration.validated()) + Data("\n".utf8)
    }

    public static func save(_ configuration: PaddrConfiguration, to url: URL? = nil) throws {
        guard let destination = url else {
            throw PaddrError.configuration(
                "Legacy raw configuration saves require an explicit destination. The default path is owned by the profile store."
            )
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            if (try? ConfigurationProfileStore.isProfileDocument(existing)) == true {
                throw PaddrError.configuration(
                    "Legacy raw configuration cannot replace a profile document at \(destination.path)."
                )
            }
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoded(configuration).write(to: destination, options: .atomic)
    }

    static func defaultCandidateURL(fileManager: FileManager, homeDirectory: URL) -> URL {
        let relativePaths = [
            ".config/Paddr/config.json",
            ".config/PuckPads/config.json",
            ".config/TracksBack/config.json",
            ".config/TrackIsBack/config.json"
        ]
        return relativePaths
            .map { homeDirectory.appendingPathComponent($0) }
            .first { fileManager.fileExists(atPath: $0.path) }
            ?? homeDirectory.appendingPathComponent(relativePaths[0])
    }
}
