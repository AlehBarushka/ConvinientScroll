nonisolated struct HottestSensors {
    static let keep = 4
    static let rescanEvery = 15

    let count: Int
    private(set) var isFullScan = true
    private var hot: [Int] = []
    private var samplesSinceScan = 0

    init(count: Int) {
        self.count = count
    }

    mutating func nextIndices() -> [Int] {
        isFullScan = hot.isEmpty || samplesSinceScan >= Self.rescanEvery - 1
        if isFullScan {
            samplesSinceScan = 0
            return Array(0..<count)
        }
        samplesSinceScan += 1
        return hot
    }

    mutating func recordFullScan(_ readings: [(index: Int, celsius: Double)]) {
        hot = readings
            .filter { $0.celsius.isFinite && CPUSensors.plausibleRange.contains($0.celsius) }
            .sorted { $0.celsius > $1.celsius }
            .prefix(Self.keep)
            .map(\.index)
            .sorted()
    }
}
