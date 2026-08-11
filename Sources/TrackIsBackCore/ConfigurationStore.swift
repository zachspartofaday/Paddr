import Foundation

public enum ConfigurationStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/PuckPads/config.json")
    }

    private static var tracksBackLegacyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/TracksBack/config.json")
    }

    private static var trackIsBackLegacyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/TrackIsBack/config.json")
    }

    public static func load(from url: URL? = nil) throws -> TrackIsBackConfiguration {
        let candidate: URL
        if let url {
            candidate = url
        } else if FileManager.default.fileExists(atPath: defaultURL.path) {
            candidate = defaultURL
        } else if FileManager.default.fileExists(atPath: tracksBackLegacyURL.path) {
            candidate = tracksBackLegacyURL
        } else {
            candidate = trackIsBackLegacyURL
        }
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
}
