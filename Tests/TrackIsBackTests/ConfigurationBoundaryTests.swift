import XCTest
@testable import TrackIsBackCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class ConfigurationBoundaryTests: XCTestCase {
    func testDefaultConfigurationPathUsesCurrentProductName() {
        XCTAssertTrue(ConfigurationStore.defaultURL.path.hasSuffix("/.config/Paddr/config.json"))
    }

    func testPuckPadsConfigurationIsTheFirstLegacyMigrationCandidate() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = home.appendingPathComponent(".config/PuckPads/config.json")
        let older = home.appendingPathComponent(".config/TracksBack/config.json")
        defer { try? fileManager.removeItem(at: home) }
        try fileManager.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: older.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: legacy)
        try Data().write(to: older)

        XCTAssertEqual(
            ConfigurationStore.defaultCandidateURL(fileManager: fileManager, homeDirectory: home),
            legacy
        )
    }

    func testMissingImplicitConfigurationUsesDefaults() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }

        let loaded = try ConfigurationStore.load(
            from: nil,
            fileManager: .default,
            homeDirectory: home
        )

        XCTAssertEqual(loaded, .default)
    }

    func testMissingExplicitConfigurationIsRejected() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")

        XCTAssertThrowsError(try ConfigurationStore.load(from: missing)) { error in
            XCTAssertTrue(String(describing: error).contains("does not exist"))
            XCTAssertTrue(String(describing: error).contains(missing.path))
        }
    }

    func testExplicitConfigurationMustBeARegularFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try ConfigurationStore.load(from: directory)) { error in
            XCTAssertTrue(String(describing: error).contains("not a regular file"))
        }
    }

    func testUnreadableExplicitConfigurationIsRejected() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0)],
            ofItemAtPath: file.path
        )

        XCTAssertThrowsError(try ConfigurationStore.load(from: file)) { error in
            XCTAssertTrue(String(describing: error).contains("Could not load configuration"))
        }
    }

    func testMalformedExplicitConfigurationIsRejected() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not-json".utf8).write(to: file)

        XCTAssertThrowsError(try ConfigurationStore.load(from: file)) { error in
            XCTAssertTrue(String(describing: error).contains("Could not load configuration"))
        }
    }

    func testValidExplicitConfigurationLoads() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: file) }
        var expected = TrackIsBackConfiguration.default
        expected.left.sensitivity = 4.2
        try ConfigurationStore.encoded(expected).write(to: file)

        XCTAssertEqual(try ConfigurationStore.load(from: file), expected)
    }

    func testEveryInclusiveConfigurationBoundaryIsAccepted() throws {
        for sensitivity in [0.1, 20] {
            for milliseconds in [1.0, 5_000] {
                for movement in [0.0, 100_000] {
                    for radius in [0.0, 1.0] {
                        let pad = PadConfiguration(
                            mode: .mouse,
                            sensitivity: sensitivity,
                            mouseDeadzone: radius,
                            tapMaximumMilliseconds: milliseconds,
                            tapMaximumMovement: movement,
                            dpadDeadzone: 0
                        )
                        XCTAssertNoThrow(try configuration(pad).validated())
                    }
                }
            }
        }
        var upperDeadzone = PadConfiguration(mode: .dpad)
        upperDeadzone.dpadDeadzone = 1.nextDown
        XCTAssertNoThrow(try configuration(upperDeadzone).validated())
    }

    func testAdjacentInvalidConfigurationValuesAreRejected() {
        assertInvalid(\.sensitivity, 0.1.nextDown)
        assertInvalid(\.sensitivity, 20.nextUp)
        assertInvalid(\.tapMaximumMilliseconds, 1.nextDown)
        assertInvalid(\.tapMaximumMilliseconds, 5_000.nextUp)
        assertInvalid(\.tapMaximumMovement, -Double.leastNonzeroMagnitude)
        assertInvalid(\.tapMaximumMovement, 100_000.nextUp)
        assertInvalid(\.mouseDeadzone, -Double.leastNonzeroMagnitude)
        assertInvalid(\.mouseDeadzone, 1.nextUp)
        assertInvalid(\.dpadDeadzone, -Double.leastNonzeroMagnitude)
        assertInvalid(\.dpadDeadzone, 1)
    }

    func testScrollConversionClampsWithoutTrapping() {
        XCTAssertEqual(CGEventOutput.clampedScrollValue(.greatestFiniteMagnitude), .max)
        XCTAssertEqual(CGEventOutput.clampedScrollValue(-.greatestFiniteMagnitude), .min)
        XCTAssertEqual(CGEventOutput.clampedScrollValue(.infinity), 0)
        XCTAssertEqual(CGEventOutput.clampedScrollValue(12.6), 13)
    }

    #if canImport(CoreGraphics)
    func testMouseMovementUsesDragEventForHeldMappedButton() {
        XCTAssertEqual(CGEventOutput.mouseMovementEventType(heldButtons: []), .mouseMoved)
        XCTAssertEqual(CGEventOutput.mouseMovementEventType(heldButtons: [.left]), .leftMouseDragged)
        XCTAssertEqual(CGEventOutput.mouseMovementEventType(heldButtons: [.right]), .rightMouseDragged)
        XCTAssertEqual(
            CGEventOutput.mouseMovementEventType(heldButtons: [.left, .right]),
            .leftMouseDragged
        )
    }
    #endif

    private func assertInvalid(_ keyPath: WritableKeyPath<PadConfiguration, Double>, _ value: Double) {
        var pad = PadConfiguration(mode: .mouse)
        pad[keyPath: keyPath] = value
        XCTAssertThrowsError(try configuration(pad).validated())
    }

    private func configuration(_ pad: PadConfiguration) -> TrackIsBackConfiguration {
        TrackIsBackConfiguration(left: pad, right: .init(mode: .disabled))
    }
}
