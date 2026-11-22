nonisolated struct SensorReading: Equatable, Sendable {
    var name: String
    var celsius: Double
}

nonisolated enum CPUSensors {
    static let plausibleRange: ClosedRange<Double> = 10...130

    private static let dieMarkers = ["tdie", "acc mtr", "soc mtr"]

    static func isCPUDie(name: String) -> Bool {
        let name = name.lowercased()
        guard !name.contains("tcal") else { return false }
        return dieMarkers.contains { name.contains($0) }
    }

    static func hottest(_ readings: [SensorReading]) -> Double? {
        readings.map(\.celsius).filter { $0.isFinite && plausibleRange.contains($0) }.max()
    }

    static func isCPUKey(_ key: String, type: String) -> Bool {
        (key.hasPrefix("Tp") || key.hasPrefix("Te")) && type == "flt "
    }
}
