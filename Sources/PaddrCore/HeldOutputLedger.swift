import Synchronization

struct OutputReleaseFailure: Equatable, Sendable {
    let action: TrackpadOutputAction
    let diagnostic: String
}

struct OutputReleaseAttempt: Equatable, Sendable {
    let failures: [OutputReleaseFailure]
    let pendingOutputs: [HeldOutput]

    var isDrained: Bool { pendingOutputs.isEmpty }

    var diagnostic: String {
        let pending = pendingOutputs
            .map(HeldOutputLedger.releaseAction(for:))
            .map(\.description)
            .joined(separator: ", ")
        let attempts = failures
            .map { "\($0.action.description): \($0.diagnostic)" }
            .joined(separator: "; ")
        if attempts.isEmpty { return "pending \(pending)" }
        return "pending \(pending); \(attempts)"
    }
}

/// Tracks physical key and mouse-button obligations independently from mapper ownership.
///
/// Calls to the wrapped sink and corresponding ledger mutations share one mutex. The sink must
/// throw before committing a singleton action; a successful return means that action was posted.
final class HeldOutputLedger: TrackpadOutputDispatching, Sendable {
    private struct State: ~Copyable {
        let sink: any TrackpadOutputDispatching
        var pending: Set<HeldOutput> = []
    }

    private let state: Mutex<State>

    init(output: any TrackpadOutputDispatching) {
        state = Mutex(State(sink: output))
    }

    var pendingOutputs: [HeldOutput] {
        state.withLock { state in
            state.pending.sorted(by: Self.isOrderedBefore)
        }
    }

    func dispatch(_ actions: [TrackpadOutputAction]) throws {
        try state.withLock { state in
            for action in actions {
                try state.sink.dispatch([action])
                Self.recordSuccessful(action, in: &state.pending)
            }
        }
    }

    func releasePending(maxPasses: Int) -> OutputReleaseAttempt {
        state.withLock { state in
            var failures: [OutputReleaseFailure] = []
            for _ in 0..<max(0, maxPasses) {
                let pending = state.pending.sorted(by: Self.isOrderedBefore)
                guard !pending.isEmpty else { break }
                for output in pending {
                    let action = Self.releaseAction(for: output)
                    do {
                        try state.sink.dispatch([action])
                        state.pending.remove(output)
                    } catch {
                        failures.append(OutputReleaseFailure(
                            action: action,
                            diagnostic: String(describing: error)
                        ))
                    }
                }
            }
            return OutputReleaseAttempt(
                failures: failures,
                pendingOutputs: state.pending.sorted(by: Self.isOrderedBefore)
            )
        }
    }

    private static func recordSuccessful(
        _ action: TrackpadOutputAction,
        in pending: inout Set<HeldOutput>
    ) {
        switch action {
        case let .key(key, isPressed):
            if isPressed { pending.insert(.key(key)) } else { pending.remove(.key(key)) }
        case let .mouseButton(button, isPressed):
            if isPressed {
                pending.insert(.mouseButton(button))
            } else {
                pending.remove(.mouseButton(button))
            }
        case .mouseMove, .scroll:
            break
        }
    }

    static func releaseAction(for output: HeldOutput) -> TrackpadOutputAction {
        switch output {
        case let .key(key): .key(key, isPressed: false)
        case let .mouseButton(button): .mouseButton(button, isPressed: false)
        }
    }

    private static func isOrderedBefore(_ lhs: HeldOutput, _ rhs: HeldOutput) -> Bool {
        switch (lhs, rhs) {
        case let (.key(left), .key(right)):
            if left.keyCode != right.keyCode { return left.keyCode < right.keyCode }
            return left.name < right.name
        case (.key, .mouseButton):
            return true
        case (.mouseButton, .key):
            return false
        case let (.mouseButton(left), .mouseButton(right)):
            return left.rawValue < right.rawValue
        }
    }
}
