import AppKit
import Combine
import OSLog

/// Runs the memory module: a menu bar segment with the share of RAM in use. It reads
/// statistics on a 2 s timer only while the module is on and the display is awake;
/// pressure colours come from system events.
@MainActor
final class MemoryController: MenuBarModule {
    private let monitor = MemoryMonitor(read: SystemMemory.usage, schedule: RepeatingTimer.dispatch)
    private var isEnabled = false
    private(set) var segment: MenuBarSegment?
    var onChange: (() -> Void)?
    private let detailItem: NSMenuItem = {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()
    var menuItems: [NSMenuItem] { [detailItem] }
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pauseObserver: WorkspacePauseObserver?

    init() {
        monitor.onDisplayChange = { [weak self] in self?.show($0) }
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
        show(monitor.display)
        monitor.pressureChanged(SystemMemory.pressure())
        startPressureSource()
        observeWorkspace()
        monitor.setEnabled(true)
        AppLog.memory.info("Memory module started")
    }

    private func stop() {
        monitor.setEnabled(false)
        pauseObserver?.stop()
        pauseObserver = nil
        for reason in PauseReason.allCases {
            monitor.setPaused(false, for: reason)
        }
        pressureSource?.cancel()
        pressureSource = nil
        show(monitor.display)
    }

    private func startPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.pressureSource?.data else { return }
                self.monitor.pressureChanged(Self.pressure(from: event))
            }
        }
        source.resume()
        pressureSource = source
    }

    private static func pressure(from event: DispatchSource.MemoryPressureEvent) -> MemoryPressure {
        if event.contains(.critical) { return .critical }
        if event.contains(.warning) { return .warning }
        return .normal
    }

    private func observeWorkspace() {
        pauseObserver = WorkspacePauseObserver { [weak self] reason, paused in
            guard let self else { return }
            if !paused { self.monitor.pressureChanged(SystemMemory.pressure()) }
            self.monitor.setPaused(paused, for: reason)
        }
    }

    // MARK: Menu bar

    private func show(_ display: MemoryMonitor.Display) {
        segment = isEnabled ? display.segment : nil
        onChange?()
    }

    func menuWillOpen() {
        detailItem.title = monitor.currentUsage()?.detailText(pressure: monitor.display.pressure)
            ?? "Memory usage is unavailable"
    }

    func menuDidClose() {}
}
