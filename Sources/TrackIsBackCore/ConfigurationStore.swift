import Foundation

public enum ConfigurationStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/Paddr/config.json")
    }

    public static func load(from url: URL? = nil) throws -> TrackIsBackConfiguration {
        let candidate = url ?? defaultCandidateURL(
            fileManager: .default,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        guard FileManager.default.fileExists(atPath: candidate.path) else { return .default }
        do {
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
