import AppKit
import Combine
import OSLog

@MainActor
final class ThermalController: NSObject, NSMenuDelegate {
    var alertsEnabled: Bool {
        get { monitor.alertsEnabled }
        set { monitor.alertsEnabled = newValue }
    }

    private let sampling = SamplingQueue()
    private let pressure = ThermalPressureSource()
    private lazy var monitor = ThermalMonitor(read: sampling.read, schedule: RepeatingTimer.dispatch)
    private var isEnabled = false
    private var statusItem: NSStatusItem?
    private var detailItem: NSMenuItem?
    private var statisticsItem: NSMenuItem?
    private var pauseObserver: WorkspacePauseObserver?

    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    override init() {
        super.init()
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
        makeStatusItem()
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
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        detailItem = nil
        statisticsItem = nil
        AppLog.thermal.info("Thermal module stopped")
    }

    // MARK: Menu bar

    private func makeStatusItem() {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "CPU temperature")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        let textWidth = ("188°" as NSString).size(withAttributes: [.font: font]).width
        let item = NSStatusBar.system.statusItem(withLength: ceil((image?.size.width ?? 0) + textWidth + 8))
        item.autosaveName = "MacToolkitThermal"
        if let button = item.button {
            button.image = image
            button.imagePosition = .imageLeading
            button.font = font
        }

        let menu = NSMenu()
        menu.delegate = self
        let detail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        let statistics = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statistics.isEnabled = false
        menu.addItem(statistics)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        item.menu = menu

        statusItem = item
        detailItem = detail
        statisticsItem = statistics
        show(monitor.display)
    }

    private func show(_ display: ThermalMonitor.Display) {
        guard let button = statusItem?.button else { return }
        let text = ThermalText.menuBar(celsius: display.celsius)
        let color: NSColor? = switch display.level?.tint ?? .none {
        case .none: nil
        case .warning: .systemYellow
        case .critical: .systemRed
        }
        button.contentTintColor = color
        if let color {
            button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        } else {
            button.title = text
        }
        let level = display.level?.title.lowercased() ?? "unknown"
        button.setAccessibilityValue("CPU \(text), thermal pressure \(level)")
    }

    private func refreshMenu() {
        detailItem?.title = ThermalText.detail(
            celsius: monitor.display.celsius,
            fanPercent: monitor.lastSample?.fanPercent,
            level: monitor.display.level
        )
        statisticsItem?.title = ThermalText.statistics(monitor.statistics.durations(at: Date()))
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
        monitor.onUpdate = { [weak self] in self?.refreshMenu() }
    }

    func menuDidClose(_ menu: NSMenu) {
        monitor.onUpdate = nil
    }

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            AppLog.thermal.error("Activity Monitor not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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

    func read(_ completion: @escaping @MainActor (ThermalSample) -> Void) {
        queue.async {
            let sample = self.sampler?.sample() ?? ThermalSample(celsius: nil, fanPercent: nil)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(sample) } }
        }
    }
}
