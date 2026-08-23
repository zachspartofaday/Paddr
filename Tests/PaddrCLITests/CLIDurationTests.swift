import XCTest
import PaddrCLIKit

final class CLIDurationTests: XCTestCase {
    func testFinitePositiveFractionParsesExactly() throws {
        XCTAssertEqual(try CLIDuration(argument: "0.25").runtimeValue, .milliseconds(250))
    }

    func testNonNumbersAndNonFiniteValuesAreRejected() {
        for value in ["not-a-number", "nan", "inf", "-inf"] {
            XCTAssertThrowsError(try CLIDuration(argument: value), value)
        }
    }

    func testNonPositiveValuesAreRejected() {
        for value in ["0", "-0.1"] {
            XCTAssertThrowsError(try CLIDuration(argument: value), value)
        }
    }

    func testValueThatWouldTrapDurationConversionIsRejectedFirst() {
        XCTAssertThrowsError(try CLIDuration(argument: "1e20"))
    }
}
