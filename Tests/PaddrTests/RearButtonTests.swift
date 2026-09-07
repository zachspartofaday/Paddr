import Foundation
import XCTest
@testable import PaddrCore

final class RearButtonTests: XCTestCase {
    func testEachRearBitInEveryLayoutAndAllTruncatedLengths() throws {
        let masks: [(RearButton, UInt32)] = [(.l4, 0x20000), (.l5, 0x40000), (.r4, 0x80), (.r5, 0x100)]
        for id: UInt8 in [0x42, 0x45, 0x47] {
            let length = id == 0x47 ? 32 : 30
            for (button, mask) in masks {
                var bytes = [UInt8](repeating: 0, count: length)
                bytes[0] = id
                for offset in 0..<4 { bytes[2 + offset] = UInt8(truncatingIfNeeded: mask >> (8 * offset)) }
                let state = try XCTUnwrap(TritonParser.parseControllerState(bytes, timestampNanoseconds: 42))
                for candidate in RearButton.allCases {
                    XCTAssertEqual(state.rearButtons.isPressed(candidate), candidate == button)
                }
                XCTAssertFalse(state.rearButtons.isNeutral)
                XCTAssertEqual(state.pads.left.timestampNanoseconds, 42)
                XCTAssertEqual(TritonParser.parseTrackpads(bytes, timestampNanoseconds: 42), state.pads)
                for count in 0..<length {
                    XCTAssertNil(TritonParser.parseControllerState(Array(bytes.prefix(count)), timestampNanoseconds: 42))
                }
            }
            var bytes = [UInt8](repeating: 0, count: length)
            bytes[0] = id
            XCTAssertTrue(try XCTUnwrap(TritonParser.parseControllerState(bytes, timestampNanoseconds: 0)).rearButtons.isNeutral)
            // Neighboring non-rear bits must not become presses.
            let unrelated: UInt32 = 0x0009_0240
            for offset in 0..<4 { bytes[2 + offset] = UInt8(truncatingIfNeeded: unrelated >> (8 * offset)) }
            XCTAssertTrue(try XCTUnwrap(TritonParser.parseControllerState(bytes, timestampNanoseconds: 0)).rearButtons.isNeutral)
            let all: UInt32 = 0x0006_0180
            for offset in 0..<4 { bytes[2 + offset] = UInt8(truncatingIfNeeded: all >> (8 * offset)) }
            let state = try XCTUnwrap(TritonParser.parseControllerState(bytes, timestampNanoseconds: 0))
            XCTAssertTrue(RearButton.allCases.allSatisfy(state.rearButtons.isPressed))
        }
        XCTAssertNil(TritonParser.parseControllerState([UInt8](repeating: 0, count: 64), timestampNanoseconds: 0))
    }

    func testDefaultsLegacyNullMissingAndValidatedBindings() throws {
        for json in ["{}", "{\"rearButtons\":null}", "{\"rearButtons\":{}}", "{\"rearButtons\":{\"l4\":null}}"] {
            let config = try JSONDecoder().decode(PaddrConfiguration.self, from: Data(json.utf8)).validated()
            XCTAssertEqual(config.rearButtons, .unassigned)
        }
        XCTAssertEqual(PaddrConfiguration.default.rearButtons, .unassigned)
        var configuration = PaddrConfiguration(left: .init(mode: .disabled), right: .init(mode: .disabled))
        configuration.rearButtons = .init(l4: " F1 ", l5: "ESC", r4: "mouse-left", r5: "code:118")
        let validated = try configuration.validated()
        XCTAssertEqual(validated.rearButtons, .init(l4: "f1", l5: "escape", r4: "mouse-left", r5: "code:118"))
        XCTAssertEqual(try JSONDecoder().decode(PaddrConfiguration.self, from: JSONEncoder().encode(validated)), validated)
        for button in RearButton.allCases {
            for invalid in ["", "none", "bogus", "code:65536"] {
                configuration.rearButtons = .unassigned
                configuration.rearButtons[button] = invalid
                XCTAssertThrowsError(try configuration.validated())
            }
        }
        for (name, code): (String, UInt16) in [("f1", 122), ("f2", 120), ("f3", 99), ("f4", 118)] {
            XCTAssertEqual(try KeyCatalog.resolve(name.uppercased()), KeyBinding(name: name, keyCode: code))
            XCTAssertTrue(KeyCatalog.commonNames.contains(name))
        }
    }

    func testProfileRoundTripDuplicateAndReplacementRetainRearBindings() throws {
        var config = PaddrConfiguration.default
        config.rearButtons = .init(l4: "f1", l5: "mouse-left", r4: "f3", r5: "f4")
        var document = ConfigurationProfileDocument.default
        let profile = try document.createProfile(named: "Rear", configuration: config)
        try document.activateProfile(id: profile.id)
        let decoded = try JSONDecoder().decode(ConfigurationProfileDocument.self, from: ConfigurationProfileStore.encoded(document))
        XCTAssertEqual(decoded.activeProfile?.configuration.rearButtons, config.rearButtons)
        let duplicate = try document.createProfile(named: "Copy", configuration: try XCTUnwrap(decoded.activeProfile).configuration)
        XCTAssertEqual(duplicate.configuration.rearButtons, config.rearButtons)
        config.rearButtons.l4 = nil
        try document.replaceConfiguration(for: profile.id, with: config)
        XCTAssertEqual(document.profile(matching: profile.id.rawValue)?.configuration.rearButtons, config.rearButtons)
        XCTAssertEqual(document.profile(matching: duplicate.id.rawValue)?.configuration.rearButtons.l4, "f1")
    }
}
