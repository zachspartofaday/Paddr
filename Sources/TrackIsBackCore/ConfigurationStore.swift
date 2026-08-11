import Foundation

public enum ConfigurationStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/Paddr/config.json")
    }

    public static func load(from url: URL? = nil) throws -> TrackIsBackConfiguration {
        try load(
            from: url,
            fileManager: .default,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func load(
        from url: URL?,
        fileManager: FileManager,
        homeDirectory: URL
    ) throws -> TrackIsBackConfiguration {
        let isExplicitURL = url != nil
        let candidate = url ?? defaultCandidateURL(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )
        guard fileManager.fileExists(atPath: candidate.path) else {
            if isExplicitURL {
                throw TrackIsBackError.configuration(
                    "Configuration file does not exist at \(candidate.path)."
                )
            }
            return .default
        }
        do {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw TrackIsBackError.configuration(
                    "Configuration path is not a regular file: \(candidate.path)."
                )
            }
            let data = try Data(contentsOf: candidate)
            return try JSONDecoder().decode(TrackIsBackConfiguration.self, from: data).validated()
        } catch let error as TrackIsBackError {
            throw error
        } catch {
            throw TrackIsBackError.configuration("Could not load configuration at \(candidate.path): \(error)")
        }
    }

    public static func encoded(_ configuration: TrackIsBackConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration.validated()) + Data("\n".utf8)
    }

    public static func save(_ configuration: TrackIsBackConfiguration, to url: URL? = nil) throws {
        let destination = url ?? defaultURL
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
