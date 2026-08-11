import TrackIsBackCore

public enum ZoneNavigationDirection: Sendable {
    case left
    case right
    case up
    case down
    case previous
    case next
}

public enum ZoneSelectionPolicy {
    public static func normalized(_ selection: ButtonZone, for layout: PadZoneLayout) -> ButtonZone {
        layout.zones.contains(selection) ? selection : layout.zones[0]
    }

    public static func moved(
        from selection: ButtonZone,
        direction: ZoneNavigationDirection,
        in layout: PadZoneLayout
    ) -> ButtonZone {
        let zones = layout.zones
        let current = normalized(selection, for: layout)
        guard let index = zones.firstIndex(of: current) else { return zones[0] }

        if layout == .radialFour {
            switch direction {
            case .left: return .left
            case .right: return .right
            case .up: return .up
            case .down: return .down
            case .previous, .next: break
            }
        }

        switch direction {
        case .previous:
            return zones[(index - 1 + zones.count) % zones.count]
        case .next:
            return zones[(index + 1) % zones.count]
        case .left, .right, .up, .down:
            break
        }

        guard let origin = coordinate(for: current, in: layout) else { return current }
        let candidates = zones.compactMap { zone -> (ButtonZone, GridCoordinate)? in
            guard let coordinate = coordinate(for: zone, in: layout) else { return nil }
            switch direction {
            case .left where coordinate.column < origin.column,
                 .right where coordinate.column > origin.column,
                 .up where coordinate.row < origin.row,
                 .down where coordinate.row > origin.row:
                return (zone, coordinate)
            default:
                return nil
            }
        }

        return candidates.min { lhs, rhs in
            navigationScore(from: origin, to: lhs.1, direction: direction)
                < navigationScore(from: origin, to: rhs.1, direction: direction)
        }?.0 ?? current
    }

    private struct GridCoordinate {
        let column: Int
        let row: Int
    }

    private static func coordinate(for zone: ButtonZone, in layout: PadZoneLayout) -> GridCoordinate? {
        switch layout {
        case .radialFour:
            switch zone {
            case .up: return GridCoordinate(column: 1, row: 0)
            case .right: return GridCoordinate(column: 2, row: 1)
            case .down: return GridCoordinate(column: 1, row: 2)
            case .left: return GridCoordinate(column: 0, row: 1)
            default: return nil
            }
        case .fourCorners:
            switch zone {
            case .topLeft: return GridCoordinate(column: 0, row: 0)
            case .topRight: return GridCoordinate(column: 1, row: 0)
            case .bottomRight: return GridCoordinate(column: 1, row: 1)
            case .bottomLeft: return GridCoordinate(column: 0, row: 1)
            default: return nil
            }
        case .horizontalTwo:
            switch zone {
            case .left: return GridCoordinate(column: 0, row: 0)
            case .right: return GridCoordinate(column: 1, row: 0)
            default: return nil
            }
        case .verticalTwo:
            switch zone {
            case .up: return GridCoordinate(column: 0, row: 0)
            case .down: return GridCoordinate(column: 0, row: 1)
            default: return nil
            }
        case .gridNine:
            guard let index = layout.zones.firstIndex(of: zone) else { return nil }
            return GridCoordinate(column: index % 3, row: index / 3)
        }
    }

    private static func navigationScore(
        from origin: GridCoordinate,
        to candidate: GridCoordinate,
        direction: ZoneNavigationDirection
    ) -> Int {
        let horizontal = abs(candidate.column - origin.column)
        let vertical = abs(candidate.row - origin.row)
        switch direction {
        case .left, .right: return horizontal * 10 + vertical
        case .up, .down: return vertical * 10 + horizontal
        case .previous, .next: return 0
        }
    }
}
