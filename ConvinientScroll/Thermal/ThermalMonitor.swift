import Combine
import Foundation

@MainActor
final class ThermalMonitor {
    struct Display: Equatable {
        var celsius: Int?
        var level: ThermalLevel?
    }

    typealias Read = (_ completion: @escaping @MainActor (ThermalSample) -> Void) -> Void

    static let interval: TimeInterval = 2

    var onDisplayChange: ((Display) -> Void)?
    var onUpdate: (() -> Void)?
    var onAlert: ((ThrottleAlert) -> Void)?
    var alertsEnabled = true
    private(set) var display = Display(celsius: nil, level: nil)
    private(set) var lastSample: ThermalSample?
    private(set) var history = ThermalHistory()
    private(set) var statistics = ThermalStatistics()

    private let read: Read
    private let schedule: RepeatingTimer.Schedule
    private let now: () -> Date
    private var isEnabled = false
    private var pauseReasons: Set<PauseReason> = []
    private var ticker: AnyCancellable?
    private var generation = 0
    private var isReading = false
    private var needsDisplay = true
    private var alertPolicy = ThrottleAlertPolicy()

    init(read: @escaping Read, schedule: @escaping RepeatingTimer.Schedule, now: @escaping () -> Date = Date.init) {
        self.read = read
        self.schedule = schedule
        self.now = now
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            statistics.start(level: display.level, at: now())
            if pauseReasons.contains(.systemSleep) { statistics.pause(at: now()) }
            resumeIfPossible()
        } else {
            stopReading()
            history.removeAll()
            statistics.reset()
            lastSample = nil
            display.celsius = nil
            needsDisplay = true
        }
    }

    func setPaused(_ paused: Bool, for reason: PauseReason) {
        if paused {
            let wasRunning = pauseReasons.isEmpty
            guard pauseReasons.insert(reason).inserted, isEnabled else { return }
            if reason == .systemSleep { statistics.pause(at: now()) }
            guard wasRunning else { return }
            stopReading()
            history.breakLine()
        } else {
            guard pauseReasons.remove(reason) != nil, isEnabled else { return }
            if reason == .systemSleep { statistics.resume(at: now()) }
            if pauseReasons.isEmpty { resumeIfPossible() }
        }
    }

    func levelChanged(_ level: ThermalLevel?) {
        let previous = display.level
        guard isEnabled else {
            display.level = level
            return
        }
        guard level != previous else { return }
        if alertsEnabled, let alert = alertPolicy.alert(from: previous, to: level, at: now()) {
            onAlert?(alert)
        }
        statistics.levelChanged(level, at: now())
        var next = display
        next.level = level
        publish(next)
        onUpdate?()
    }

    private func resumeIfPossible() {
        guard isEnabled, pauseReasons.isEmpty, ticker == nil else { return }
        refresh()
        ticker = schedule(Self.interval, Self.interval * 0.2) { [weak self] in self?.refresh() }
    }

    private func stopReading() {
        ticker = nil
        generation += 1
        isReading = false
    }

    private func refresh() {
        guard !isReading else { return }
        isReading = true
        let generation = generation
        read { [weak self] sample in self?.accept(sample, generation: generation) }
    }

    private func accept(_ sample: ThermalSample, generation: Int) {
        guard generation == self.generation else { return }
        isReading = false
        history.append(sample, level: display.level, at: now())
        lastSample = sample
        var next = display
        next.celsius = sample.celsius.map { Int($0.rounded()) }
        publish(next)
        onUpdate?()
    }

    private func publish(_ next: Display) {
        guard needsDisplay || next != display else { return }
        display = next
        needsDisplay = false
        onDisplayChange?(next)
    }
}
