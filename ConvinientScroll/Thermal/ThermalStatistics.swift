import Foundation

nonisolated struct LevelDuration: Equatable {
    let level: ThermalLevel
    let seconds: TimeInterval
}

nonisolated struct ThermalStatistics {
    private var isStarted = false
    private var isPaused = false
    private var level: ThermalLevel?
    private var since: Date?
    private var totals: [ThermalLevel: TimeInterval] = [:]

    mutating func start(level: ThermalLevel?, at date: Date) {
        reset()
        isStarted = true
        self.level = level
        since = date
    }

    mutating func levelChanged(_ level: ThermalLevel?, at date: Date) {
        guard isStarted else { return }
        accrue(until: date)
        self.level = level
    }

    mutating func pause(at date: Date) {
        guard isStarted, !isPaused else { return }
        accrue(until: date)
        isPaused = true
        since = nil
    }

    mutating func resume(at date: Date) {
        guard isStarted, isPaused else { return }
        isPaused = false
        since = date
    }

    func durations(at now: Date) -> [LevelDuration] {
        guard isStarted else { return [] }
        var totals = totals
        if let level, let since { totals[level, default: 0] += now.timeIntervalSince(since) }
        return ThermalLevel.allCases.compactMap { level in
            guard let seconds = totals[level], seconds > 0 else { return nil }
            return LevelDuration(level: level, seconds: seconds)
        }
    }

    mutating func reset() {
        self = ThermalStatistics()
    }

    private mutating func accrue(until date: Date) {
        guard let since else { return }
        if let level { totals[level, default: 0] += date.timeIntervalSince(since) }
        self.since = date
    }
}
