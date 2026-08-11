public enum OutputSource: String, CaseIterable, Hashable, Sendable {
    case leftPad
    case rightPad
}

public enum HeldOutput: Hashable, Sendable {
    case key(KeyBinding)
    case mouseButton(MouseButtonBinding)
}

public struct OutputArbiter: Sendable {
    private var owners: [HeldOutput: Set<OutputSource>] = [:]

    public init() {}

    public mutating func process(
        _ actions: [TrackpadOutputAction],
        from source: OutputSource
    ) -> [TrackpadOutputAction] {
        var emitted: [TrackpadOutputAction] = []
        var index = actions.startIndex
        while index < actions.endIndex {
            let action = actions[index]
            let nextIndex = actions.index(after: index)
            if let release = transition(for: action), !release.isPressed,
               nextIndex < actions.endIndex,
               let press = transition(for: actions[nextIndex]),
               press.isPressed,
               press.output == release.output,
               owners[release.output, default: []].contains(source) {
                index = actions.index(after: nextIndex)
                continue
            }
            if let press = transition(for: action), press.isPressed,
               nextIndex < actions.endIndex,
               let release = transition(for: actions[nextIndex]),
               !release.isPressed,
               release.output == press.output {
                if owners[press.output, default: []].isEmpty {
                    emitted.append(action)
                    emitted.append(actions[nextIndex])
                }
                index = actions.index(after: nextIndex)
                continue
            }

            guard let transition = transition(for: action) else {
                emitted.append(action)
                index = nextIndex
                continue
            }

            var currentOwners = owners[transition.output, default: []]
            if transition.isPressed {
                guard currentOwners.insert(source).inserted else {
                    index = nextIndex
                    continue
                }
                owners[transition.output] = currentOwners
                if currentOwners.count == 1 { emitted.append(action) }
            } else {
                guard currentOwners.remove(source) != nil else {
                    index = nextIndex
                    continue
                }
                if currentOwners.isEmpty {
                    owners.removeValue(forKey: transition.output)
                    emitted.append(action)
                } else {
                    owners[transition.output] = currentOwners
                }
            }
            index = nextIndex
        }
        return emitted
    }

    public mutating func releaseAll() -> [TrackpadOutputAction] {
        let releases = owners.keys.sorted(by: Self.isOrderedBefore).map(Self.releaseAction)
        owners.removeAll(keepingCapacity: true)
        return releases
    }

    private func transition(for action: TrackpadOutputAction) -> (output: HeldOutput, isPressed: Bool)? {
        switch action {
        case let .key(key, isPressed): return (.key(key), isPressed)
        case let .mouseButton(button, isPressed): return (.mouseButton(button), isPressed)
        case .mouseMove, .scroll: return nil
        }
    }

    private static func releaseAction(for output: HeldOutput) -> TrackpadOutputAction {
        switch output {
        case let .key(key): return .key(key, isPressed: false)
        case let .mouseButton(button): return .mouseButton(button, isPressed: false)
        }
    }

    private static func isOrderedBefore(_ lhs: HeldOutput, _ rhs: HeldOutput) -> Bool {
        sortKey(lhs) < sortKey(rhs)
    }

    private static func sortKey(_ output: HeldOutput) -> String {
        switch output {
        case let .key(key): return "key:\(key.keyCode)"
        case let .mouseButton(button): return "mouse:\(button.rawValue)"
        }
    }
}
