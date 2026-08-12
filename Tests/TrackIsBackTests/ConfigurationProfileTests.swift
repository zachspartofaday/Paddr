import Foundation
import XCTest
@testable import TrackIsBackCore

final class ConfigurationProfileTests: XCTestCase {
    func testCanonicalDocumentRoundTripsIndependentCompleteConfigurations() throws {
        var first = TrackIsBackConfiguration.default
        first.left.sensitivity = 2.5
        first.left.mouseAcceleration = 0.3
        first.right.tapKey = "space"
        var second = TrackIsBackConfiguration.default
        second.left.mode = .dpad
        second.left.zoneLayout = .gridNine
        second.left.gridKeys.center = "return"
        second.right.scrollSensitivity = 0.4

        var document = ConfigurationProfileDocument.default
        let firstProfile = try document.createProfile(
            named: "Work",
            configuration: first,
            id: id("00000000-0000-0000-0000-000000000010")
        )
        _ = try document.createProfile(
            named: "Game",
            configuration: second,
            id: id("00000000-0000-0000-0000-000000000011")
        )
        document.activeProfileID = firstProfile.id

        let decoded = try JSONDecoder().decode(
            ConfigurationProfileDocument.self,
            from: ConfigurationProfileStore.encoded(document)
        )

        XCTAssertEqual(try decoded.validated(), document)
        XCTAssertEqual(decoded.userProfiles[0].configuration, first)
        XCTAssertEqual(decoded.userProfiles[1].configuration, second)
    }

    func testDefaultProfileIsStableAndNotStoredAsMutableData() throws {
        let data = try ConfigurationProfileStore.encoded(.default)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(ConfigurationProfile.default.id, .default)
        XCTAssertEqual(ConfigurationProfile.default.name, "Default")
        XCTAssertEqual(ConfigurationProfile.default.configuration, .default)
        XCTAssertFalse(json.contains("\"name\" : \"Default\""))
        XCTAssertFalse(json.contains("\"left\""))
    }

    func testStableIDSurvivesRenameAndDrivesActivation() throws {
        let stableID = id("00000000-0000-0000-0000-000000000012")
        var document = ConfigurationProfileDocument.default
        _ = try document.createProfile(named: "Original", id: stableID)

        try document.renameProfile(id: stableID, to: "Renamed")
        try document.activateProfile(id: stableID)

        XCTAssertEqual(document.activeProfileID, stableID)
        XCTAssertEqual(document.activeProfile?.name, "Renamed")
        XCTAssertNil(document.profile(matching: "Original"))
    }

    func testUUIDTextCaseHasOneCanonicalIdentityAcrossDecodeValidationLookupAndEncoding() throws {
        let lowercase = "a0000000-0000-0000-0000-000000000012"
        let uppercase = lowercase.uppercased()
        let decodedUppercase = try JSONDecoder().decode(
            ConfigurationProfileID.self,
            from: Data("\"\(uppercase)\"".utf8)
        )

        XCTAssertEqual(decodedUppercase, id(lowercase))
        XCTAssertEqual(decodedUppercase.rawValue, lowercase)

        var document = ConfigurationProfileDocument.default
        let profile = try document.createProfile(named: "Original", id: id(lowercase))
        XCTAssertEqual(document.profile(matching: uppercase), profile)
        XCTAssertThrowsError(
            try document.createProfile(named: "Collision", id: id(uppercase))
        )

        let encoded = try XCTUnwrap(
            String(data: ConfigurationProfileStore.encoded(document), encoding: .utf8)
        )
        XCTAssertTrue(encoded.contains(lowercase))
        XCTAssertFalse(encoded.contains(uppercase))
    }

    func testUUIDTextCaseCollisionInImportedDocumentIsRejectedAsDuplicate() throws {
        let lowercase = "a0000000-0000-0000-0000-000000000013"
        let uppercase = lowercase.uppercased()
        let replacedID = "b0000000-0000-0000-0000-000000000013"
        var source = ConfigurationProfileDocument.default
        _ = try source.createProfile(named: "First", id: id(lowercase))
        _ = try source.createProfile(named: "Second", id: id(replacedID))
        let importedJSON = try XCTUnwrap(String(data: rawEncoded(source), encoding: .utf8))
            .replacingOccurrences(of: replacedID, with: uppercase)
        let imported = try JSONDecoder().decode(
            ConfigurationProfileDocument.self,
            from: Data(importedJSON.utf8)
        )

        XCTAssertEqual(imported.userProfiles[0].id, imported.userProfiles[1].id)
        XCTAssertThrowsError(try imported.validated()) { error in
            XCTAssertTrue(String(describing: error).contains("IDs must be unique"))
        }
    }

    func testNamesAreTrimmedNonemptyAndCaseInsensitivelyUnique() throws {
        var document = ConfigurationProfileDocument.default
        let profile = try document.createProfile(
            named: "  Gaming  ",
            id: id("00000000-0000-0000-0000-000000000013")
        )
        XCTAssertEqual(profile.name, "Gaming")

        XCTAssertThrowsError(
            try document.createProfile(
                named: "gAmInG",
                id: id("00000000-0000-0000-0000-000000000014")
            )
        )
        XCTAssertThrowsError(
            try document.createProfile(
                named: " \n ",
                id: id("00000000-0000-0000-0000-000000000015")
            )
        )
        XCTAssertThrowsError(try document.renameProfile(id: profile.id, to: "default"))
    }

    func testUUIDShapedNamesAreRejectedForCreateAndRenameAfterNormalization() throws {
        let lowercaseUUID = "a0000000-0000-0000-0000-000000000030"
        let proposedNames = [
            lowercaseUUID,
            lowercaseUUID.uppercased(),
            " \n\(lowercaseUUID.uppercased())\t "
        ]

        for proposedName in proposedNames {
            var createDocument = ConfigurationProfileDocument.default
            XCTAssertThrowsError(
                try createDocument.createProfile(
                    named: proposedName,
                    id: id("b0000000-0000-0000-0000-000000000030")
                )
            ) { error in
                XCTAssertTrue(String(describing: error).contains("cannot be UUIDs"))
            }
            XCTAssertTrue(createDocument.userProfiles.isEmpty)

            var renameDocument = ConfigurationProfileDocument.default
            let profile = try renameDocument.createProfile(
                named: "Normal name",
                id: id("b0000000-0000-0000-0000-000000000031")
            )
            XCTAssertThrowsError(
                try renameDocument.renameProfile(id: profile.id, to: proposedName)
            ) { error in
                XCTAssertTrue(String(describing: error).contains("cannot be UUIDs"))
            }
            XCTAssertEqual(renameDocument.profile(id: profile.id)?.name, "Normal name")
        }
    }

    func testImportedDocumentRejectsUUIDShapedNameBeforeSelection() throws {
        let profileID = id("b0000000-0000-0000-0000-000000000032")
        let document = ConfigurationProfileDocument(
            activeProfileID: profileID,
            userProfiles: [
                ConfigurationProfile(
                    id: profileID,
                    name: " A0000000-0000-0000-0000-000000000033 ",
                    configuration: .default
                )
            ]
        )

        XCTAssertThrowsError(try document.validated()) { error in
            XCTAssertTrue(String(describing: error).contains("cannot be UUIDs"))
        }
    }

    func testDuplicateUsesDeterministicCopySuffixes() throws {
        let sourceID = id("00000000-0000-0000-0000-000000000016")
        var document = ConfigurationProfileDocument.default
        _ = try document.createProfile(named: "Gaming", id: sourceID)

        let first = try document.duplicateProfile(
            id: sourceID,
            newID: id("00000000-0000-0000-0000-000000000017")
        )
        let second = try document.duplicateProfile(
            id: sourceID,
            newID: id("00000000-0000-0000-0000-000000000018")
        )

        XCTAssertEqual(first.name, "Gaming Copy")
        XCTAssertEqual(second.name, "Gaming Copy 2")
    }

    func testDefaultCannotBeRenamedDeletedOrCustomized() throws {
        var document = ConfigurationProfileDocument.default

        XCTAssertThrowsError(try document.renameProfile(id: .default, to: "Other"))
        XCTAssertThrowsError(try document.deleteProfile(id: .default))
        var changed = TrackIsBackConfiguration.default
        changed.left.sensitivity = 3
        XCTAssertThrowsError(try document.replaceConfiguration(for: .default, with: changed))
        XCTAssertNoThrow(try document.replaceConfiguration(for: .default, with: .default))
    }

    func testDeletingActiveProfileFallsBackToDefaultAndInactiveDeleteKeepsSelection() throws {
        var document = ConfigurationProfileDocument.default
        let first = try document.createProfile(
            named: "First",
            id: id("00000000-0000-0000-0000-000000000019")
        )
        let second = try document.createProfile(
            named: "Second",
            id: id("00000000-0000-0000-0000-000000000020")
        )
        try document.activateProfile(id: first.id)

        try document.deleteProfile(id: second.id)
        XCTAssertEqual(document.activeProfileID, first.id)
        try document.deleteProfile(id: first.id)
        XCTAssertEqual(document.activeProfileID, .default)
    }

    func testLegacyDefaultMigratesToCanonicalDefault() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try ConfigurationStore.encoded(.default).write(to: fixture.url)

        let result = try ConfigurationProfileStore.load(
            from: nil,
            fileManager: .default,
            homeDirectory: fixture.home,
            writeAtomically: { try $0.write(to: $1, options: .atomic) }
        )

        XCTAssertEqual(result.document, .default)
        XCTAssertEqual(
            try JSONDecoder().decode(ConfigurationProfileDocument.self, from: Data(contentsOf: fixture.url)),
            .default
        )
    }

    func testCustomizedLegacyMigrationPreservesDecodedModelExactly() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        var legacy = TrackIsBackConfiguration.default
        legacy.left.sensitivity = 7.25
        legacy.left.scrollSensitivity = 0.35
        legacy.right.mouseAcceleration = 0.8
        legacy.right.tapKey = "space"
        try ConfigurationStore.encoded(legacy).write(to: fixture.url)

        let result = try ConfigurationProfileStore.load(
            from: nil,
            fileManager: .default,
            homeDirectory: fixture.home,
            writeAtomically: { try $0.write(to: $1, options: .atomic) }
        )

        XCTAssertEqual(result.document.activeProfile?.name, "Previous configuration")
        XCTAssertEqual(result.document.activeProfile?.configuration, legacy)
        XCTAssertEqual(result.document.userProfiles.count, 1)
    }

    func testMigrationFailurePreservesOriginalBytes() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        var legacy = TrackIsBackConfiguration.default
        legacy.left.sensitivity = 5
        let original = try ConfigurationStore.encoded(legacy)
        try original.write(to: fixture.url)

        XCTAssertThrowsError(
            try ConfigurationProfileStore.load(
                from: nil,
                fileManager: .default,
                homeDirectory: fixture.home,
                writeAtomically: { _, _ in throw TestFailure.expected }
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("original file"))
            XCTAssertTrue(String(describing: error).contains(fixture.url.path))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.url), original)
    }

    func testLegacySaveWithoutExplicitDestinationFailsClosed() {
        XCTAssertThrowsError(try ConfigurationStore.save(.default)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("explicit destination"))
            XCTAssertTrue(message.contains("profile store"))
        }
    }

    func testLegacySaveCannotReplaceCanonicalProfileDocument() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        var document = ConfigurationProfileDocument.default
        _ = try document.createProfile(
            named: "First",
            id: id("00000000-0000-0000-0000-000000000034")
        )
        let active = try document.createProfile(
            named: "Second",
            id: id("00000000-0000-0000-0000-000000000035")
        )
        try document.activateProfile(id: active.id)
        let original = try ConfigurationProfileStore.encoded(document)
        try original.write(to: fixture.url)

        XCTAssertThrowsError(try ConfigurationStore.save(.default, to: fixture.url)) { error in
            XCTAssertTrue(String(describing: error).contains("profile document"))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.url), original)
        let reloaded = try ConfigurationProfileStore.load(from: fixture.url)
        XCTAssertEqual(reloaded.document, document)
        XCTAssertEqual(reloaded.document.userProfiles.count, 2)
        XCTAssertEqual(reloaded.document.activeProfileID, active.id)
    }

    func testExplicitLegacySaveToNewPathStillRoundTripsRawConfiguration() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let legacyURL = fixture.home.appendingPathComponent("legacy.json")
        var configuration = TrackIsBackConfiguration.default
        configuration.left.sensitivity = 3.5

        try ConfigurationStore.save(configuration, to: legacyURL)

        XCTAssertEqual(try ConfigurationStore.load(from: legacyURL), configuration)
    }

    func testAtomicSaveFailurePreservesExistingCanonicalDocument() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let original = try ConfigurationProfileStore.encoded(.default)
        try original.write(to: fixture.url)
        var changed = ConfigurationProfileDocument.default
        _ = try changed.createProfile(
            named: "New",
            id: id("00000000-0000-0000-0000-000000000021")
        )

        XCTAssertThrowsError(
            try ConfigurationProfileStore.save(
                changed,
                to: fixture.url,
                fileManager: .default,
                writeAtomically: { _, _ in throw TestFailure.expected }
            )
        )
        XCTAssertEqual(try Data(contentsOf: fixture.url), original)
    }

    func testMissingActiveIDFailsClosedWithoutDroppingProfilesAndPreservesDiagnostic() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        var document = ConfigurationProfileDocument.default
        let profile = try document.createProfile(
            named: "Recoverable",
            id: id("00000000-0000-0000-0000-000000000022")
        )
        document.activeProfileID = id("00000000-0000-0000-0000-000000000099")
        try rawEncoded(document).write(to: fixture.url)

        let result = try ConfigurationProfileStore.load(
            from: fixture.url,
            fileManager: .default,
            homeDirectory: fixture.home,
            writeAtomically: { _, _ in XCTFail("Repair must not silently rewrite storage") }
        )

        XCTAssertEqual(result.document.activeProfileID, .default)
        XCTAssertEqual(result.document.profile(id: profile.id)?.name, "Recoverable")
        XCTAssertTrue(try XCTUnwrap(result.diagnostic).contains("missing"))
    }

    func testCorruptCanonicalStorageIsRejectedWithoutModification() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let corrupt = Data("{\"schemaVersion\":1,\"activeProfileID\":false}".utf8)
        try corrupt.write(to: fixture.url)

        XCTAssertThrowsError(try ConfigurationProfileStore.load(from: fixture.url))
        XCTAssertEqual(try Data(contentsOf: fixture.url), corrupt)
    }

    func testSavedDocumentRelaunchesWithSameActiveStableID() throws {
        let fixture = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        var document = ConfigurationProfileDocument.default
        let profile = try document.createProfile(
            named: "Persistent",
            id: id("00000000-0000-0000-0000-000000000023")
        )
        try document.activateProfile(id: profile.id)
        try ConfigurationProfileStore.save(document, to: fixture.url)

        let reloaded = try ConfigurationProfileStore.load(from: fixture.url)

        XCTAssertEqual(reloaded.document, document)
        XCTAssertEqual(reloaded.document.activeProfileID, profile.id)
    }

    private func id(_ rawValue: String) -> ConfigurationProfileID {
        ConfigurationProfileID(rawValue: rawValue)
    }

    private func temporaryStore() throws -> (home: URL, url: URL) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = home.appendingPathComponent(".config/Paddr/config.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return (home, url)
    }

    private func rawEncoded(_ document: ConfigurationProfileDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}

private enum TestFailure: Error {
    case expected
}
