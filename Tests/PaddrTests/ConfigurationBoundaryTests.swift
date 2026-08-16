import XCTest
@testable import PaddrCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class ConfigurationBoundaryTests: XCTestCase {
    func testDefaultConfigurationPathUsesCurrentProductName() {
        XCTAssertTrue(ConfigurationStore.defaultURL.path.hasSuffix("/.config/Paddr/config.json"))
        XCTAssertEqual(ConfigurationStore.defaultURL, ConfigurationProfileStore.defaultURL)
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

    func testTracksBackConfigurationIsUsedWhenItIsTheOnlyCandidate() throws {
        let (home, candidate) = try isolatedConfiguration(at: ".config/TracksBack/config.json")
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(
            ConfigurationStore.defaultCandidateURL(fileManager: .default, homeDirectory: home),
            candidate
        )
    }

    func testTrackIsBackConfigurationIsUsedWhenItIsTheOnlyCandidate() throws {
        let (home, candidate) = try isolatedConfiguration(at: ".config/TrackIsBack/config.json")
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(
            ConfigurationStore.defaultCandidateURL(fileManager: .default, homeDirectory: home),
            candidate
        )
    }

    func testConfigurationCandidateUsesFullCurrentToOldestPrecedence() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let candidates: [(relativePath: String, configuration: TrackIsBackConfiguration)] = [
            (".config/Paddr/config.json", configuration(PadConfiguration(mode: .mouse, sensitivity: 1))),
            (".config/PuckPads/config.json", configuration(PadConfiguration(mode: .mouse, sensitivity: 2))),
            (".config/TracksBack/config.json", configuration(PadConfiguration(mode: .mouse, sensitivity: 3))),
            (".config/TrackIsBack/config.json", configuration(PadConfiguration(mode: .mouse, sensitivity: 4)))
        ]
        defer { try? fileManager.removeItem(at: home) }
        for candidate in candidates {
            let file = home.appendingPathComponent(candidate.relativePath)
            try fileManager.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try ConfigurationStore.encoded(candidate.configuration).write(to: file)
        }

        for candidate in candidates {
            let loaded = try ConfigurationStore.load(
                from: nil,
                fileManager: fileManager,
                homeDirectory: home
            )
            XCTAssertEqual(loaded, candidate.configuration)
            try fileManager.removeItem(at: home.appendingPathComponent(candidate.relativePath))
        }
    }

    func testOldSchemaDocumentSuppliesEveryAddedPadDefault() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: file) }
        let oldSchema = """
        {
          "left": { "mode": "scroll" },
          "right": { "mode": "mouse", "sensitivity": 2.75 }
        }
        """
        try Data(oldSchema.utf8).write(to: file)

        let loaded = try ConfigurationStore.load(from: file)
        assertOldSchemaDefaults(in: loaded.left, mode: .scroll, sensitivity: 1)
        assertOldSchemaDefaults(in: loaded.right, mode: .mouse, sensitivity: 2.75)
        XCTAssertEqual(loaded.left.scrollSensitivity, 1)
        XCTAssertEqual(loaded.right.scrollSensitivity, 1)
        XCTAssertEqual(loaded.left.mouseAcceleration, 0)
        XCTAssertEqual(loaded.right.mouseAcceleration, 0)
    }

    func testOldSchemaMissingWholePadUsesCoupledFallback() throws {
        let missingRight = try JSONDecoder().decode(
            TrackIsBackConfiguration.self,
            from: Data("{\"left\":{\"mode\":\"scroll\"}}".utf8)
        )
        let missingLeft = try JSONDecoder().decode(
            TrackIsBackConfiguration.self,
            from: Data("{\"right\":{\"mode\":\"mouse\"}}".utf8)
        )

        XCTAssertEqual(missingRight.left.centerTapTrackingMode, .coupled)
        XCTAssertEqual(missingRight.right.mode, .mouse)
        XCTAssertEqual(missingRight.right.centerTapTrackingMode, .coupled)
        XCTAssertEqual(missingLeft.left.mode, .scroll)
        XCTAssertEqual(missingLeft.left.centerTapTrackingMode, .coupled)
        XCTAssertEqual(missingLeft.right.centerTapTrackingMode, .coupled)
    }

    func testNewPadAndBuiltInDefaultsUseDecoupledCenterTapTracking() {
        XCTAssertEqual(CenterTapTrackingMode.coupled.rawValue, "coupled")
        XCTAssertEqual(CenterTapTrackingMode.decoupled.rawValue, "decoupled")
        XCTAssertEqual(
            PadConfiguration(mode: .mouse).centerTapTrackingMode,
            .decoupled
        )
        XCTAssertEqual(TrackIsBackConfiguration.default.left.centerTapTrackingMode, .decoupled)
        XCTAssertEqual(TrackIsBackConfiguration.default.right.centerTapTrackingMode, .decoupled)
    }

    func testCenterTapTrackingModeEncodesAndRoundTripsIndependentlyForBothPads() throws {
        var expected = TrackIsBackConfiguration.default
        expected.left.centerTapTrackingMode = .coupled
        expected.right.centerTapTrackingMode = .decoupled

        let data = try ConfigurationStore.encoded(expected)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let left = try XCTUnwrap(object["left"] as? [String: Any])
        let right = try XCTUnwrap(object["right"] as? [String: Any])

        XCTAssertEqual(left["centerTapTrackingMode"] as? String, "coupled")
        XCTAssertEqual(right["centerTapTrackingMode"] as? String, "decoupled")
        XCTAssertEqual(
            try JSONDecoder().decode(TrackIsBackConfiguration.self, from: data),
            expected
        )
    }

    func testOldSchemaScrollSensitivityCarriesExistingValueBelowOne() throws {
        let configuration = try JSONDecoder().decode(
            TrackIsBackConfiguration.self,
            from: Data(
                """
                {
                  "left": { "mode": "scroll", "sensitivity": 0.4 },
                  "right": { "mode": "mouse", "sensitivity": 12 }
                }
                """.utf8
            )
        )

        XCTAssertEqual(configuration.left.scrollSensitivity, 0.4)
        XCTAssertEqual(configuration.right.scrollSensitivity, 1)
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

    func testScrollSensitivityRoundTripsIndependently() throws {
        var expected = TrackIsBackConfiguration.default
        expected.left.sensitivity = 12
        expected.left.scrollSensitivity = 0.4

        XCTAssertEqual(
            try JSONDecoder().decode(
                TrackIsBackConfiguration.self,
                from: ConfigurationStore.encoded(expected)
            ),
            expected
        )
    }

    func testMouseAccelerationRoundTripsIndependentlyForBothPads() throws {
        var expected = TrackIsBackConfiguration.default
        expected.left.mouseAcceleration = 0.25
        expected.right.mouseAcceleration = 0.75

        let decoded = try JSONDecoder().decode(
            TrackIsBackConfiguration.self,
            from: ConfigurationStore.encoded(expected)
        )

        XCTAssertEqual(decoded.left.mouseAcceleration, 0.25)
        XCTAssertEqual(decoded.right.mouseAcceleration, 0.75)
        XCTAssertEqual(decoded, expected)
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
                            centerTapTrackingMode: .decoupled,
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

    func testScrollSensitivityInclusiveBoundariesAreAccepted() {
        for scrollSensitivity in [0.0, 1.0] {
            let pad = PadConfiguration(mode: .scroll, scrollSensitivity: scrollSensitivity)
            XCTAssertNoThrow(try configuration(pad).validated())
        }
    }

    func testMouseAccelerationInclusiveBoundariesAreAccepted() {
        for mouseAcceleration in [0.0, 1.0] {
            let pad = PadConfiguration(mode: .mouse, mouseAcceleration: mouseAcceleration)
            XCTAssertNoThrow(try configuration(pad).validated())
        }
    }

    func testAdjacentInvalidConfigurationValuesAreRejected() {
        assertInvalid(\.sensitivity, 0.1.nextDown)
        assertInvalid(\.sensitivity, 20.nextUp)
        assertInvalid(\.scrollSensitivity, -Double.leastNonzeroMagnitude)
        assertInvalid(\.scrollSensitivity, 1.nextUp)
        assertInvalid(\.mouseAcceleration, -Double.leastNonzeroMagnitude)
        assertInvalid(\.mouseAcceleration, 1.nextUp)
        assertInvalid(\.mouseAcceleration, .nan)
        assertInvalid(\.mouseAcceleration, .infinity)
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

    private func assertOldSchemaDefaults(
        in pad: PadConfiguration,
        mode: PadMode,
        sensitivity: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(pad.mode, mode, file: file, line: line)
        XCTAssertEqual(pad.sensitivity, sensitivity, file: file, line: line)
        XCTAssertEqual(pad.mouseAcceleration, 0, file: file, line: line)
        XCTAssertEqual(pad.mouseDeadzone, 0, file: file, line: line)
        XCTAssertEqual(pad.centerTapTrackingMode, .coupled, file: file, line: line)
        XCTAssertNil(pad.tapKey, file: file, line: line)
        XCTAssertEqual(pad.tapMaximumMilliseconds, 250, file: file, line: line)
        XCTAssertEqual(pad.tapMaximumMovement, 2_200, file: file, line: line)
        XCTAssertEqual(pad.dpadDeadzone, 0.22, file: file, line: line)
        XCTAssertEqual(pad.zoneLayout, .radialFour, file: file, line: line)
        XCTAssertEqual(
            pad.dpadKeys,
            DirectionKeyConfiguration(up: "up", right: "right", down: "down", left: "left"),
            file: file,
            line: line
        )
        XCTAssertEqual(
            pad.gridKeys,
            GridKeyConfiguration(
                topLeft: "q", top: "w", topRight: "e",
                left: "a", center: "space", right: "d",
                bottomLeft: "z", bottom: "x", bottomRight: "c"
            ),
            file: file,
            line: line
        )
    }

    private func isolatedConfiguration(at relativePath: String) throws -> (home: URL, candidate: URL) {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let candidate = home.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: candidate)
        return (home, candidate)
    }

    private func assertInvalid(_ keyPath: WritableKeyPath<PadConfiguration, Double>, _ value: Double) {
        var pad = PadConfiguration(mode: .mouse)
        pad[keyPath: keyPath] = value
        XCTAssertThrowsError(try configuration(pad).validated())
    }

    private func configuration(_ pad: PadConfiguration) -> TrackIsBackConfiguration {
        TrackIsBackConfiguration(left: pad, right: .init(mode: .disabled))
    }
}
