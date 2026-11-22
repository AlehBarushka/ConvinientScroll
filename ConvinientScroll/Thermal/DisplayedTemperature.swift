nonisolated struct DisplayedTemperature {
    static let deadZone = 1.5
    static let window = 3

    private var recent: [Double] = []
    private var shown: Int?

    mutating func update(_ celsius: Double?) -> Int? {
        guard let celsius else {
            reset()
            return nil
        }
        recent.append(celsius)
        if recent.count > Self.window { recent.removeFirst() }
        let median = recent.sorted()[(recent.count - 1) / 2]
        if let shown, abs(median - Double(shown)) < Self.deadZone { return shown }
        shown = Int(median.rounded())
        return shown
    }

    mutating func reset() {
        recent = []
        shown = nil
    }
}
