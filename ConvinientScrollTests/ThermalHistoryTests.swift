import Foundation
import Testing
@testable import MacToolkit

@Suite("ThermalHistory")
struct ThermalHistoryTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func keepsTenMinutes() {
        var history = ThermalHistory()
        history.append(ThermalSample(celsius: 40, fanPercent: nil), level: .nominal, at: t0)
        history.append(ThermalSample(celsius: 41, fanPercent: nil), level: .nominal, at: t0 + 300)
        history.append(ThermalSample(celsius: 42, fanPercent: nil), level: .nominal, at: t0 + 601)
        #expect(history.points.map(\.celsius) == [41, 42])
    }

    @Test func wakeAfterHoursDropsEverythingOld() {
        var history = ThermalHistory()
        history.append(ThermalSample(celsius: 40, fanPercent: 0), level: .nominal, at: t0)
        history.breakLine()
        history.append(ThermalSample(celsius: 50, fanPercent: 0), level: .nominal, at: t0 + 8 * 3600)
        #expect(history.points.count == 1)
    }

    @Test func breakLineStartsNewSegment() {
        var history = ThermalHistory()
        history.append(ThermalSample(celsius: 40, fanPercent: nil), level: .nominal, at: t0)
        history.breakLine()
        history.append(ThermalSample(celsius: 41, fanPercent: nil), level: .nominal, at: t0 + 10)
        #expect(history.points.map(\.segment) == [0, 1])
    }

    @Test func idsKeepGrowingAfterTrim() {
        var history = ThermalHistory()
        history.append(ThermalSample(celsius: 40, fanPercent: nil), level: .nominal, at: t0)
        history.append(ThermalSample(celsius: 41, fanPercent: nil), level: .nominal, at: t0 + 700)
        history.removeAll()
        history.append(ThermalSample(celsius: 42, fanPercent: nil), level: .nominal, at: t0 + 710)
        #expect(history.points.map(\.id) == [2])
    }

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
