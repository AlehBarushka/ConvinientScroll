/// Used memory hovering at a rounding boundary (70.5 %) would flip the shown number every
/// reading; the number moves only once the reading is a full point away from it.
nonisolated struct DisplayedPercent {
    static let deadZone = 1.0

    private var shown: Int?

    mutating func update(_ percent: Double) -> Int {
        if let shown, abs(percent - Double(shown)) < Self.deadZone { return shown }
        let next = Int(min(max(percent, 0), 100).rounded())
        shown = next
        return next
    }

    mutating func reset() {
        shown = nil
    }
}
