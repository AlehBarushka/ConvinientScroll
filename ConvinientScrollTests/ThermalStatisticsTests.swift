import Foundation
import Testing
@testable import MacToolkit

@Suite("ThermalStatistics")
struct ThermalStatisticsTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func statisticsCountLevelsAndSkipPauses() {
        var stats = ThermalStatistics()
        stats.start(level: .nominal, at: t0)
        stats.levelChanged(.heavy, at: t0 + 100)
        stats.pause(at: t0 + 160)
        stats.resume(at: t0 + 3760)
        stats.levelChanged(.nominal, at: t0 + 3800)
        #expect(stats.durations(at: t0 + 3820) == [
            LevelDuration(level: .nominal, seconds: 120),
            LevelDuration(level: .heavy, seconds: 100)
        ])
    }

    @Test func unknownLevelIsNotCounted() {
        var stats = ThermalStatistics()
        stats.start(level: nil, at: t0)
        stats.levelChanged(.moderate, at: t0 + 50)
        #expect(stats.durations(at: t0 + 80) == [LevelDuration(level: .moderate, seconds: 30)])
    }

    @Test func levelChangeDuringPauseCountsFromResume() {
        var stats = ThermalStatistics()
        stats.start(level: .nominal, at: t0)
        stats.pause(at: t0 + 10)
        stats.levelChanged(.heavy, at: t0 + 20)
        stats.resume(at: t0 + 100)
        #expect(stats.durations(at: t0 + 130) == [
            LevelDuration(level: .nominal, seconds: 10),
            LevelDuration(level: .heavy, seconds: 30)
        ])
    }

    @Test func nothingBeforeStartOrAfterReset() {
        var stats = ThermalStatistics()
        #expect(stats.durations(at: t0).isEmpty)
        stats.start(level: .nominal, at: t0)
        stats.reset()
        #expect(stats.durations(at: t0 + 50).isEmpty)
    }
}
