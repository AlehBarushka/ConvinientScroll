import Combine
import Foundation
import Testing
@testable import MacToolkit

@MainActor
@Suite("ThermalMonitor")
struct ThermalMonitorTests {
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
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        private(set) var reads = 0
        private(set) var pending: [@MainActor (ThermalSample) -> Void] = []
        private(set) var shown: [ThermalMonitor.Display] = []
        private(set) var alerts: [ThrottleAlert] = []
        private(set) var updates = 0
        let monitor: ThermalMonitor

        init() {
            var harness: Harness?
            let ticker = self.ticker
            monitor = ThermalMonitor(
                read: { completion in harness?.record(completion) },
                schedule: { ticker.schedule(interval: $0, tolerance: $1, action: $2) },
                now: { harness?.clock ?? .distantPast }
            )
            harness = self
            monitor.onDisplayChange = { [unowned self] in self.shown.append($0) }
            monitor.onAlert = { [unowned self] in self.alerts.append($0) }
            monitor.onUpdate = { [unowned self] in self.updates += 1 }
        }

        private func record(_ completion: @escaping @MainActor (ThermalSample) -> Void) {
            reads += 1
            pending.append(completion)
        }

        func answer(_ celsius: Double?, fan: Int? = nil) {
            guard !pending.isEmpty else { Issue.record("no read in flight"); return }
            pending.removeFirst()(ThermalSample(celsius: celsius, fanPercent: fan))
        }

        func tick(answer celsius: Double?) {
            clock += ThermalMonitor.interval
            ticker.fire()
            answer(celsius)
        }
    }

    @Test func enablingReadsAtOnceAndTicksEveryTwoSeconds() {
        let h = Harness()
        h.monitor.setEnabled(true)

        #expect(h.reads == 1)
        #expect(h.ticker.schedules.count == 1)
        #expect(h.ticker.schedules.first?.interval == 2)
        #expect(h.ticker.schedules.first?.tolerance == 0.4)
    }

    @Test func sameWholeDegreeDoesNotRedraw() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.answer(34.9)
        h.tick(answer: 35.2)
        h.tick(answer: 36.6)

        #expect(h.shown.map(\.celsius) == [35, 37])
        #expect(h.updates == 3)
        #expect(h.monitor.history.points.map(\.celsius) == [34.9, 35.2, 36.6])
    }

    @Test func levelColourRedrawsWithoutReading() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.answer(35)
        h.monitor.levelChanged(.heavy)

        #expect(h.shown.last == ThermalMonitor.Display(celsius: 35, level: .heavy))
        #expect(h.reads == 1)
    }

    @Test func tickDuringReadDoesNotStartAnother() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.ticker.fire()
        h.ticker.fire()

        #expect(h.reads == 1)
    }

    @Test func lateAnswerAfterDisableIsIgnored() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.monitor.setEnabled(false)
        h.answer(50)

        #expect(h.monitor.history.points.isEmpty)
        #expect(h.monitor.display.celsius == nil)
        #expect(h.monitor.lastSample == nil)
    }

    @Test func lateAnswerAfterPauseIsIgnored() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.answer(40)
        h.clock += 2
        h.ticker.fire()
        h.monitor.setPaused(true, for: .displaySleep)
        h.answer(60)

        #expect(h.monitor.history.points.count == 1)
        #expect(h.monitor.display.celsius == 40)
    }

    @Test func pauseStopsTicksAndBreaksTheLine() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.answer(40)
        h.monitor.setPaused(true, for: .systemSleep)

        #expect(!h.ticker.isActive)

        h.clock += 60
        h.monitor.setPaused(false, for: .systemSleep)
        #expect(h.reads == 2)
        #expect(h.ticker.isActive)
        h.answer(45)

        #expect(h.monitor.history.points.map(\.segment) == [0, 1])
    }

    @Test func resumeWaitsForEveryReason() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.answer(40)
        h.monitor.setPaused(true, for: .systemSleep)
        h.monitor.setPaused(true, for: .displaySleep)
        h.monitor.setPaused(false, for: .systemSleep)

        #expect(h.reads == 1)
        #expect(!h.ticker.isActive)
    }

    @Test func levelWhileDisabledIsKeptAndSilent() {
        let h = Harness()
        h.monitor.levelChanged(.critical)

        #expect(h.alerts.isEmpty)
        #expect(h.shown.isEmpty)

        h.monitor.setEnabled(true)
        #expect(h.monitor.display.level == .critical)
        h.answer(80)
        #expect(h.shown.last == ThermalMonitor.Display(celsius: 80, level: .critical))
    }

    @Test func alertsFollowPolicyAndToggle() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.monitor.levelChanged(.moderate)
        h.monitor.levelChanged(.heavy)

        #expect(h.alerts == [.heavy])

        h.monitor.alertsEnabled = false
        h.monitor.levelChanged(.critical)

        #expect(h.alerts == [.heavy])
    }

    @Test func disablingClearsHistoryAndStatistics() {
        let h = Harness()
        h.monitor.levelChanged(.nominal)
        h.monitor.setEnabled(true)
        h.answer(40)
        h.clock += 30
        h.monitor.setEnabled(false)

        #expect(h.monitor.history.points.isEmpty)
        #expect(h.monitor.statistics.durations(at: h.clock).isEmpty)
    }

    @Test func reenablingRedrawsEvenWithTheSameReading() {
        let h = Harness()
        h.monitor.setEnabled(true)
        h.answer(40)
        h.monitor.setEnabled(false)
        h.monitor.setEnabled(true)
        h.answer(40)

        #expect(h.shown.map(\.celsius) == [40, 40])
    }
}
