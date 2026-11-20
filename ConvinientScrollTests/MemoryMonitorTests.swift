import Combine
import Foundation
import Testing
@testable import MacToolkit

@MainActor
@Suite("MemoryMonitor")
struct MemoryMonitorTests {
    @MainActor
    final class FakeTicker {
        private(set) var schedules: [(interval: TimeInterval, tolerance: TimeInterval)] = []
        private var action: (() -> Void)?

        var isActive: Bool { action != nil }

        func schedule(interval: TimeInterval, tolerance: TimeInterval, action: @escaping () -> Void) -> AnyCancellable {
            schedules.append((interval, tolerance))
            self.action = action
            return AnyCancellable { [weak self] in self?.action = nil }
        }

        func fire() { action?() }
    }

    @MainActor
    final class Harness {
        let ticker = FakeTicker()
        var readings: [UInt64?] = []
        private(set) var readCount = 0
        private(set) var shown: [MemoryMonitor.Display] = []
        let monitor: MemoryMonitor

        static let gib: UInt64 = 1 << 30

        init() {
            var harness: Harness?
            let ticker = self.ticker
            monitor = MemoryMonitor(
                read: { harness?.nextReading() },
                schedule: { ticker.schedule(interval: $0, tolerance: $1, action: $2) }
            )
            harness = self
            monitor.onDisplayChange = { [unowned self] in self.shown.append($0) }
        }

        private func nextReading() -> MemoryUsage? {
            readCount += 1
            guard !readings.isEmpty, let used = readings.removeFirst() else { return nil }
            return MemoryUsage(usedBytes: used, totalBytes: 32 * Self.gib)
        }

        func gb(_ value: Double) -> UInt64 { UInt64(value * Double(Self.gib)) }
    }

    @Test func enablingReadsAtOnceAndTicksEveryTwoSecondsWithTolerance() {
        let h = Harness()
        h.readings = [h.gb(16)]
        h.monitor.setEnabled(true)

        #expect(h.shown == [.init(percent: 50, pressure: .normal)])
        #expect(h.ticker.schedules.count == 1)
        #expect(h.ticker.schedules.first?.interval == 2)
        #expect(h.ticker.schedules.first?.tolerance == 0.4)
    }

    @Test func sameWholePercentDoesNotRedraw() {
        let h = Harness()
        h.readings = [h.gb(16), h.gb(16.05), h.gb(19.2)]
        h.monitor.setEnabled(true)
        h.ticker.fire()
        h.ticker.fire()

        #expect(h.shown.map(\.percent) == [50, 60])
    }

    @Test func failedReadKeepsTheLastValue() {
        let h = Harness()
        h.readings = [h.gb(16), nil]
        h.monitor.setEnabled(true)
        h.ticker.fire()

        #expect(h.shown.map(\.percent) == [50])
        #expect(h.monitor.display.percent == 50)
    }

    @Test func failedFirstReadShowsNoPercent() {
        let h = Harness()
        h.readings = [nil]
        h.monitor.setEnabled(true)

        #expect(h.shown == [.init(percent: nil, pressure: .normal)])
    }

    @Test func pressureChangeRedrawsWithoutReading() {
        let h = Harness()
        h.readings = [h.gb(16)]
        h.monitor.setEnabled(true)
        let reads = h.readCount

        h.monitor.pressureChanged(.warning)
        h.monitor.pressureChanged(.warning)
        h.monitor.pressureChanged(.critical)

        #expect(h.readCount == reads)
        #expect(h.shown.map(\.pressure) == [.normal, .warning, .critical])
    }

    @Test func pauseStopsTicksUntilEveryReasonIsCleared() {
        let h = Harness()
        h.readings = [h.gb(16), h.gb(20)]
        h.monitor.setEnabled(true)

        h.monitor.setPaused(true, for: .displaySleep)
        h.monitor.setPaused(true, for: .sessionInactive)
        #expect(!h.ticker.isActive)

        h.monitor.setPaused(false, for: .displaySleep)
        #expect(!h.ticker.isActive)
        #expect(h.shown.map(\.percent) == [50])

        h.monitor.setPaused(false, for: .sessionInactive)
        #expect(h.ticker.isActive)
        #expect(h.shown.map(\.percent) == [50, 63])
    }

    @Test func disablingStopsTicking() {
        let h = Harness()
        h.readings = [h.gb(16)]
        h.monitor.setEnabled(true)
        h.monitor.setEnabled(false)

        #expect(!h.ticker.isActive)
        let reads = h.readCount
        h.monitor.setPaused(true, for: .systemSleep)
        h.monitor.setPaused(false, for: .systemSleep)
        #expect(h.readCount == reads)
        #expect(!h.ticker.isActive)
    }

    @Test func enablingWhilePausedWaitsForResume() {
        let h = Harness()
        h.readings = [h.gb(16)]
        h.monitor.setPaused(true, for: .systemSleep)
        h.monitor.setEnabled(true)

        #expect(h.readCount == 0)
        #expect(!h.ticker.isActive)

        h.monitor.setPaused(false, for: .systemSleep)
        #expect(h.readCount == 1)
        #expect(h.ticker.isActive)
    }

    @Test func reEnablingRedrawsEvenWithTheSameValue() {
        let h = Harness()
        h.readings = [h.gb(16), h.gb(16)]
        h.monitor.setEnabled(true)
        h.monitor.setEnabled(false)
        h.monitor.setEnabled(true)

        #expect(h.shown.map(\.percent) == [50, 50])
    }
}
