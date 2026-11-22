import Combine
import Foundation

/// Decides when to read memory statistics and when the menu bar needs a redraw.
/// System events, the timer and the status item are wired up by `MemoryController`.
@MainActor
final class MemoryMonitor {
    struct Display: Equatable {
        var percent: Int?
        var pressure: MemoryPressure
    }

    typealias PauseReason = MacToolkit.PauseReason
    typealias Schedule = RepeatingTimer.Schedule

    static let interval: TimeInterval = 2

    var onDisplayChange: ((Display) -> Void)?
    private(set) var display = Display(percent: nil, pressure: .normal)
    private(set) var lastUsage: MemoryUsage?

    private let read: () -> MemoryUsage?
    private let schedule: Schedule
    private var isEnabled = false
    private var pauseReasons: Set<PauseReason> = []
    private var ticker: AnyCancellable?
    private var needsDisplay = true

    init(read: @escaping () -> MemoryUsage?, schedule: @escaping Schedule) {
        self.read = read
        self.schedule = schedule
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            resumeIfPossible()
        } else {
            ticker = nil
            lastUsage = nil
            display.percent = nil
            needsDisplay = true
        }
    }

    func setPaused(_ paused: Bool, for reason: PauseReason) {
        if paused {
            pauseReasons.insert(reason)
            ticker = nil
        } else {
            pauseReasons.remove(reason)
            resumeIfPossible()
        }
    }

    func pressureChanged(_ pressure: MemoryPressure) {
        var next = display
        next.pressure = pressure
        if isEnabled {
            publish(next)
        } else {
            display = next
        }
    }

    /// A fresh reading for the menu, falling back to the last one if the read fails.
    func currentUsage() -> MemoryUsage? {
        refresh()
        return lastUsage
    }

    private func resumeIfPossible() {
        guard isEnabled, pauseReasons.isEmpty, ticker == nil else { return }
        refresh()
        ticker = schedule(Self.interval, Self.interval * 0.2) { [weak self] in self?.refresh() }
    }

    private func refresh() {
        guard let usage = read() else {
            if needsDisplay { publish(display) }
            return
        }
        lastUsage = usage
        var next = display
        next.percent = usage.percent
        publish(next)
    }

    private func publish(_ next: Display) {
        guard needsDisplay || next != display else { return }
        display = next
        needsDisplay = false
        onDisplayChange?(next)
    }
}

extension MemoryMonitor.Display {
    var segment: MenuBarSegment {
        let text = percent.map { "\($0)%" } ?? "—%"
        return MenuBarSegment(
            symbol: "memorychip",
            text: text,
            reservedCharacters: 4,
            tint: pressure.tint,
            accessibility: "\(text) memory used, pressure \(pressure.title.lowercased())"
        )
    }
}
