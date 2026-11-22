import Foundation

nonisolated struct ThermalSample: Equatable, Sendable {
    var celsius: Double?
    var fanPercent: Int?
}

nonisolated struct ThermalPoint: Equatable, Identifiable {
    let id: Int
    let date: Date
    let celsius: Double?
    let fanPercent: Int?
    let level: ThermalLevel?
    let segment: Int
}

nonisolated struct ThermalHistory {
    static let window: TimeInterval = 600

    private(set) var points: [ThermalPoint] = []
    private var nextID = 0
    private var segment = 0

    mutating func append(_ sample: ThermalSample, level: ThermalLevel?, at date: Date) {
        let cutoff = date - Self.window
        points.removeAll { $0.date < cutoff }
        points.append(ThermalPoint(
            id: nextID, date: date, celsius: sample.celsius, fanPercent: sample.fanPercent,
            level: level, segment: segment
        ))
        nextID += 1
    }

    mutating func breakLine() {
        segment += 1
    }

    mutating func removeAll() {
        points.removeAll()
        segment += 1
    }
}
