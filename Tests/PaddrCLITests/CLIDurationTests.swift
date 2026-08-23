import XCTest
import PaddrCLIKit
import PaddrCore
import Synchronization

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

    func testExecutionForwardsParsedDurationToRuntime() throws {
        let capture = RuntimeCapture()
        var configuration = PaddrConfiguration.default
        configuration.left.mode = .dpad
        let stopToken = TrackpadStopToken()

        let result = try CLIExecution.run(
            configuration: configuration,
            observeOnly: true,
            stopToken: stopToken,
            duration: CLIDuration(argument: "0.25"),
            onAction: { _ in },
            runtime: { capturedConfiguration, capturedObserveOnly, capturedStopToken,
                       capturedDuration, _ in
                capture.record(
                    configuration: capturedConfiguration,
                    observeOnly: capturedObserveOnly,
                    reusedStopToken: capturedStopToken === stopToken,
                    duration: capturedDuration
                )
                return TrackpadRunResult(
                    summary: .init(reportCount: 3, actionCount: 2),
                    termination: .stopped
                )
            }
        )

        XCTAssertEqual(result.summary, .init(reportCount: 3, actionCount: 2))
        XCTAssertEqual(capture.value?.configuration, configuration)
        XCTAssertEqual(capture.value?.observeOnly, true)
        XCTAssertEqual(capture.value?.reusedStopToken, true)
        XCTAssertEqual(capture.value?.duration, .milliseconds(250))
    }
}

private final class RuntimeCapture: Sendable {
    struct Value: Sendable {
        let configuration: PaddrConfiguration
        let observeOnly: Bool
        let reusedStopToken: Bool
        let duration: Duration?
    }

    private let storage = Mutex<Value?>(nil)

    var value: Value? { storage.withLock { $0 } }

    func record(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        reusedStopToken: Bool,
        duration: Duration?
    ) {
        storage.withLock {
            $0 = Value(
                configuration: configuration,
                observeOnly: observeOnly,
                reusedStopToken: reusedStopToken,
                duration: duration
            )
        }
    }
}
