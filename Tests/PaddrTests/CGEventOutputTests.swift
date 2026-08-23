#if canImport(CoreGraphics)
import CoreGraphics
import Synchronization
import XCTest
@testable import PaddrCore

final class CGEventOutputTests: XCTestCase {
    func testMouseButtonReleaseThrowsWhenCurrentLocationIsUnavailable() {
        let output = CGEventOutput(currentMouseLocation: { nil })

        XCTAssertThrowsError(
            try output.dispatch([.mouseButton(.left, isPressed: false)])
        ) { error in
            XCTAssertTrue(String(describing: error).contains("mouse location"))
        }
    }

    func testLeftButtonChangesMovementFromDragBackToMove() throws {
        let recorder = CGEventRequestRecorder()
        let output = makeOutput(recorder: recorder)

        try output.dispatch([
            .mouseButton(.left, isPressed: true),
            .mouseMove(dx: 4, dy: -3),
            .mouseButton(.left, isPressed: false),
            .mouseMove(dx: -2, dy: 5)
        ])

        XCTAssertEqual(recorder.requests, [
            .mouse(kind: .leftDown, button: .left, x: 100, y: 200),
            .mouse(kind: .leftDragged, button: .left, x: 104, y: 197),
            .mouse(kind: .leftUp, button: .left, x: 100, y: 200),
            .mouse(kind: .moved, button: .left, x: 98, y: 205)
        ])
    }

    func testRightButtonProducesRightDrag() throws {
        let recorder = CGEventRequestRecorder()
        let output = makeOutput(recorder: recorder)

        try output.dispatch([
            .mouseButton(.right, isPressed: true),
            .mouseMove(dx: 1.5, dy: 2.5)
        ])

        XCTAssertEqual(recorder.requests.last, .mouse(
            kind: .rightDragged,
            button: .right,
            x: 101.5,
            y: 202.5
        ))
    }

    func testLeftButtonTakesDragPrecedenceUntilReleased() throws {
        let recorder = CGEventRequestRecorder()
        let output = makeOutput(recorder: recorder)

        try output.dispatch([
            .mouseButton(.right, isPressed: true),
            .mouseButton(.left, isPressed: true),
            .mouseMove(dx: 2, dy: 3),
            .mouseButton(.left, isPressed: false),
            .mouseMove(dx: 6, dy: 7)
        ])

        XCTAssertEqual(recorder.requests[2], .mouse(
            kind: .leftDragged,
            button: .left,
            x: 102,
            y: 203
        ))
        XCTAssertEqual(recorder.requests[4], .mouse(
            kind: .rightDragged,
            button: .right,
            x: 106,
            y: 207
        ))
    }

    func testFailedButtonPostDoesNotChangeHeldButtonState() throws {
        let attempts = Mutex(0)
        let recorder = CGEventRequestRecorder()
        let output = CGEventOutput(
            currentMouseLocation: { CGPoint(x: 100, y: 200) },
            postEvent: { request in
                let shouldFail = attempts.withLock { count in
                    count += 1
                    return count == 1
                }
                if shouldFail { throw PaddrError.output("Injected post failure.") }
                recorder.record(request)
            }
        )

        XCTAssertThrowsError(try output.dispatch([.mouseButton(.left, isPressed: true)]))
        try output.dispatch([.mouseMove(dx: 1, dy: 1)])

        XCTAssertEqual(recorder.requests, [
            .mouse(kind: .moved, button: .left, x: 101, y: 201)
        ])
    }

    func testScrollAndKeyboardUseTheSameRequestSink() throws {
        let recorder = CGEventRequestRecorder()
        let output = makeOutput(recorder: recorder)
        let key = try KeyCatalog.resolve("a")

        try output.dispatch([
            .scroll(dx: 2.4, dy: -3.6),
            .key(key, isPressed: true)
        ])

        XCTAssertEqual(recorder.requests, [
            .scroll(horizontal: 2, vertical: -4),
            .key(code: key.keyCode, isPressed: true)
        ])
    }

    private func makeOutput(recorder: CGEventRequestRecorder) -> CGEventOutput {
        CGEventOutput(
            currentMouseLocation: { CGPoint(x: 100, y: 200) },
            postEvent: recorder.record
        )
    }
}

private final class CGEventRequestRecorder: Sendable {
    private let storage = Mutex<[CGEventRequest]>([])

    var requests: [CGEventRequest] { storage.withLock { $0 } }

    func record(_ request: CGEventRequest) {
        storage.withLock { $0.append(request) }
    }
}
#endif
