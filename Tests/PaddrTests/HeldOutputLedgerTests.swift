import Synchronization
import XCTest
@testable import PaddrCore

final class HeldOutputLedgerTests: XCTestCase {
    func testSuccessfulTransitionsTrackOnlyHeldKeysAndButtons() throws {
        let sink = DeterministicOutput()
        let ledger = HeldOutputLedger(output: sink)
        let space = try KeyCatalog.resolve("space")

        try ledger.dispatch([
            .mouseMove(dx: 1, dy: 2),
            .scroll(dx: 3, dy: 4),
            .key(space, isPressed: true),
            .mouseButton(.left, isPressed: true)
        ])

        XCTAssertEqual(ledger.pendingOutputs, [.key(space), .mouseButton(.left)])
        try ledger.dispatch([
            .key(space, isPressed: false),
            .mouseButton(.left, isPressed: false)
        ])
        XCTAssertEqual(ledger.pendingOutputs, [])
    }

    func testFailedDownCreatesNoReleaseObligation() throws {
        let sink = DeterministicOutput(failingCalls: [1])
        let ledger = HeldOutputLedger(output: sink)
        let space = try KeyCatalog.resolve("space")

        XCTAssertThrowsError(try ledger.dispatch([.key(space, isPressed: true)]))

        XCTAssertEqual(ledger.pendingOutputs, [])
        XCTAssertEqual(ledger.releasePending(maxPasses: 2).pendingOutputs, [])
        XCTAssertEqual(sink.committed, [])
    }

    func testKeyAliasesShareOnePhysicalReleaseObligation() throws {
        let sink = DeterministicOutput()
        let ledger = HeldOutputLedger(output: sink)
        let namedReturn = try KeyCatalog.resolve("return")
        let codedReturn = try KeyCatalog.resolve("code:36")

        try ledger.dispatch([
            .key(namedReturn, isPressed: true),
            .key(codedReturn, isPressed: true)
        ])

        XCTAssertEqual(ledger.pendingOutputs, [.key(namedReturn)])
        try ledger.dispatch([.key(codedReturn, isPressed: false)])
        XCTAssertEqual(ledger.pendingOutputs, [])
    }

    func testFailedUpRemainsPendingUntilRetrySucceeds() throws {
        let sink = DeterministicOutput(failingCalls: [2])
        let ledger = HeldOutputLedger(output: sink)
        let space = try KeyCatalog.resolve("space")

        try ledger.dispatch([.key(space, isPressed: true)])
        XCTAssertThrowsError(try ledger.dispatch([.key(space, isPressed: false)]))
        XCTAssertEqual(ledger.pendingOutputs, [.key(space)])

        let retry = ledger.releasePending(maxPasses: 2)

        XCTAssertTrue(retry.isDrained)
        XCTAssertEqual(retry.failures, [])
        XCTAssertEqual(sink.committed, [
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ])
    }

    func testPartialTapRetainsSuccessfulDownWhenUpThrows() throws {
        let sink = DeterministicOutput(failingCalls: [2])
        let ledger = HeldOutputLedger(output: sink)
        let space = try KeyCatalog.resolve("space")

        XCTAssertThrowsError(try ledger.dispatch([
            .key(space, isPressed: true),
            .key(space, isPressed: false)
        ]))
        XCTAssertEqual(ledger.pendingOutputs, [.key(space)])

        XCTAssertTrue(ledger.releasePending(maxPasses: 1).isDrained)
        XCTAssertEqual(sink.attempts, [
            .key(space, isPressed: true),
            .key(space, isPressed: false),
            .key(space, isPressed: false)
        ])
    }

    func testReleasePassesAttemptEveryPendingOutputInStableOrder() throws {
        let sink = DeterministicOutput(failingCalls: [3, 4, 5])
        let ledger = HeldOutputLedger(output: sink)
        let space = try KeyCatalog.resolve("space")
        try ledger.dispatch([
            .mouseButton(.left, isPressed: true),
            .key(space, isPressed: true)
        ])

        let attempt = ledger.releasePending(maxPasses: 2)

        XCTAssertEqual(attempt.pendingOutputs, [.key(space)])
        XCTAssertEqual(attempt.failures.map(\.action), [
            .key(space, isPressed: false),
            .mouseButton(.left, isPressed: false),
            .key(space, isPressed: false)
        ])
        XCTAssertEqual(Array(sink.attempts.suffix(4)), [
            .key(space, isPressed: false),
            .mouseButton(.left, isPressed: false),
            .key(space, isPressed: false),
            .mouseButton(.left, isPressed: false)
        ])
    }
}

private final class DeterministicOutput: TrackpadOutputDispatching, Sendable {
    private struct State: ~Copyable {
        var callCount = 0
        var failingCalls: Set<Int>
        var attempts: [TrackpadOutputAction] = []
        var committed: [TrackpadOutputAction] = []
    }

    private let state: Mutex<State>

    init(failingCalls: Set<Int> = []) {
        state = Mutex(State(failingCalls: failingCalls))
    }

    var attempts: [TrackpadOutputAction] { state.withLock { $0.attempts } }
    var committed: [TrackpadOutputAction] { state.withLock { $0.committed } }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        for action in actions {
            try state.withLock { state in
                state.callCount += 1
                state.attempts.append(action)
                if state.failingCalls.remove(state.callCount) != nil {
                    throw PaddrError.output("Injected failure at call \(state.callCount).")
                }
                state.committed.append(action)
            }
        }
    }
}
