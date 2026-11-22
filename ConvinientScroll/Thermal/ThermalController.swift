import AppKit
import Combine
import OSLog

@MainActor
final class ThermalController: MenuBarModule {
    var alertsEnabled: Bool {
        get { monitor.alertsEnabled }
        set { monitor.alertsEnabled = newValue }
    }

    private let sampling = SamplingQueue()
    private let pressure = ThermalPressureSource()
    private lazy var monitor = ThermalMonitor(
        read: { [weak self] completion in
            guard let self else { return }
            self.sampling.read(includeFan: self.isMenuOpen, completion)
        },
        schedule: RepeatingTimer.dispatch
    )
    private var isEnabled = false
    private var isMenuOpen = false
    private(set) var segment: MenuBarSegment?
    var onChange: (() -> Void)?
    private let detailItem = ThermalController.makeRow()
    private let statisticsItem = ThermalController.makeRow()
    var menuItems: [NSMenuItem] { [detailItem, statisticsItem] }
    private var pauseObserver: WorkspacePauseObserver?

    init() {
        monitor.onDisplayChange = { [weak self] in self?.show($0) }
        monitor.onAlert = { NotificationService.shared.showThrottling($0) }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: Lifecycle

    private func start() {
        pressure.start { [weak self] in self?.monitor.levelChanged($0) }
        monitor.levelChanged(pressure.current())
        show(monitor.display)
        sampling.start()
        pauseObserver = WorkspacePauseObserver { [weak self] reason, paused in
            guard let self else { return }
            if !paused { self.monitor.levelChanged(self.pressure.current()) }
            self.monitor.setPaused(paused, for: reason)
        }
        monitor.setEnabled(true)
        AppLog.thermal.info("Thermal module started")
    }

    private func stop() {
        monitor.setEnabled(false)
        pauseObserver?.stop()
        pauseObserver = nil
        for reason in PauseReason.allCases {
            monitor.setPaused(false, for: reason)
        }
        pressure.stop()
        sampling.stop()
        show(monitor.display)
        AppLog.thermal.info("Thermal module stopped")
    }

    // MARK: Menu bar

    private static func makeRow() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func show(_ display: ThermalMonitor.Display) {
        segment = isEnabled ? display.segment : nil
        onChange?()
    }

    private func refreshMenu() {
        detailItem.title = ThermalText.detail(
            celsius: monitor.display.celsius,
            fanPercent: monitor.lastSample?.fanPercent,
            level: monitor.display.level
        )
        statisticsItem.title = ThermalText.statistics(monitor.statistics.durations(at: Date()))
    }

    func menuWillOpen() {
        isMenuOpen = true
        refreshMenu()
        monitor.onUpdate = { [weak self] in self?.refreshMenu() }
        monitor.refreshNow()
    }

    func menuDidClose() {
        isMenuOpen = false
        monitor.onUpdate = nil
    }
}

// The sampler holds the HID client and the SMC connection; both are touched only on `queue`.
private nonisolated final class SamplingQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(AppLog.subsystem).thermal", qos: .utility)
    private var sampler: ThermalSampler?

    func start() {
        queue.async { self.sampler = ThermalSampler.live() }
    }

    func stop() {
        queue.async { self.sampler = nil }
    }

    func read(includeFan: Bool, _ completion: @escaping @MainActor (ThermalSample) -> Void) {
        queue.async {
            let sample = self.sampler?.sample(includeFan: includeFan) ?? ThermalSample(celsius: nil, fanPercent: nil)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(sample) } }
        }
    }
}
