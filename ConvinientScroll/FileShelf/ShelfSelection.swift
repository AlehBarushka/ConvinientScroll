import AppKit

nonisolated struct ShelfSelection: Equatable, Sendable {
    enum Modifier: Equatable, Sendable {
        case plain, toggle, range

        init(flags: NSEvent.ModifierFlags) {
            if flags.contains(.command) {
                self = .toggle
            } else if flags.contains(.shift) {
                self = .range
            } else {
                self = .plain
            }
        }
    }

    private(set) var ids: Set<UUID> = []
    private var rangeStart: UUID?

    /// `order` holds the selectable cards as the shelf shows them.
    mutating func click(_ id: UUID, modifier: Modifier, order: [UUID]) {
        switch modifier {
        case .range:
            if let rangeStart, let from = order.firstIndex(of: rangeStart), let to = order.firstIndex(of: id) {
                ids = Set(order[min(from, to)...max(from, to)])
            } else {
                click(id, modifier: .plain, order: order)
            }
        case .toggle:
            if ids.remove(id) == nil { ids.insert(id) }
            rangeStart = id
        case .plain:
            ids = [id]
            rangeStart = id
        }
    }

    /// Returns the cards the drag carries, in `order`.
    mutating func beginDrag(from id: UUID, order: [UUID]) -> [UUID] {
        guard ids.contains(id) else {
            clear()
            return [id]
        }
        return order.filter(ids.contains)
    }

    mutating func clear() {
        ids = []
        rangeStart = nil
    }

    mutating func retain(_ selectable: Set<UUID>) {
        ids.formIntersection(selectable)
        if let rangeStart, !selectable.contains(rangeStart) { self.rangeStart = nil }
    }
}
