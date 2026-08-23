import Foundation
import Synchronization
import XCTest

let defaultAsyncTestTimeout: Duration = .seconds(5)

@discardableResult
@concurrent
func eventually(
    timeout: Duration = defaultAsyncTestTimeout,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    repeat {
        if await condition() { return true }
        if Task.isCancelled {
            XCTFail("The test task was cancelled before the condition was satisfied.", file: file, line: line)
            return false
        }
        await Task.yield()
    } while clock.now < deadline

    if await condition() { return true }
    XCTFail("Timed out after \(timeout) waiting for the test condition.", file: file, line: line)
    return false
}

final class BoundedTestGate: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let sourceFile: StaticString
    private let sourceLine: UInt

    init(file: StaticString = #filePath, line: UInt = #line) {
        sourceFile = file
        sourceLine = line
    }

    func wait(timeout: DispatchTimeInterval = .seconds(5)) {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            XCTFail("Timed out waiting for a test gate to open.", file: sourceFile, line: sourceLine)
            return
        }
    }

    func signal() {
        semaphore.signal()
    }
}

final class SessionEventProbe<Event: Sendable>: Sendable {
    private struct State: ~Copyable {
        var events: [Event] = []
        var isFinished = false
    }

    private let state = Mutex(State())

    func record(_ event: Event) {
        state.withLock { $0.events.append(event) }
    }

    func finish() {
        state.withLock { $0.isFinished = true }
    }

    var events: [Event] {
        state.withLock { $0.events }
    }

    var isFinished: Bool {
        state.withLock { $0.isFinished }
    }

    func observe(_ stream: AsyncStream<Event>) -> Task<Void, Never> {
        Task { [self] in
            for await event in stream { record(event) }
            finish()
        }
    }

    @discardableResult
    @concurrent
    func wait(
        timeout: Duration = defaultAsyncTestTimeout,
        file: StaticString = #filePath,
        line: UInt = #line,
        until condition: @escaping @Sendable ([Event], Bool) -> Bool
    ) async -> Bool {
        await eventually(timeout: timeout, file: file, line: line) { [self] in
            let snapshot = state.withLock { (events: $0.events, isFinished: $0.isFinished) }
            return condition(snapshot.events, snapshot.isFinished)
        }
    }
}
