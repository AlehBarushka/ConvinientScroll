import AppKit
import Combine
import OSLog

/// Runs the memory module: a menu bar item with the share of RAM in use. It reads
/// statistics on a 2 s timer only while the module is on and the display is awake;
/// pressure colours come from system events.
@MainActor
final class MemoryController: NSObject, NSMenuDelegate {
    private let monitor = MemoryMonitor(read: SystemMemory.usage, schedule: RepeatingTimer.dispatch)
    private var isEnabled = false
    private var statusItem: NSStatusItem?
    private var detailItem: NSMenuItem?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pauseObserver: WorkspacePauseObserver?

    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    override init() {
        super.init()
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
        makeStatusItem()
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
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        detailItem = nil
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

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MacToolkitMemory"
        if let button = item.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Memory")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = font
        }

        let menu = NSMenu()
        menu.delegate = self
        let detail = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        item.menu = menu

        statusItem = item
        detailItem = detail
        show(monitor.display)
    }

    private func show(_ display: MemoryMonitor.Display) {
        guard let button = statusItem?.button else { return }
        let text = display.percent.map { "\($0)%" } ?? "—%"
        let color: NSColor? = switch display.pressure {
        case .normal: nil
        case .warning: .systemYellow
        case .critical: .systemRed
        }
        button.contentTintColor = color
        if let color {
            button.attributedTitle = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        } else {
            button.title = text
        }
        button.setAccessibilityValue("\(text) memory used, pressure \(display.pressure.title.lowercased())")
    }

    func menuWillOpen(_ menu: NSMenu) {
        detailItem?.title = monitor.currentUsage()?.detailText(pressure: monitor.display.pressure)
            ?? "Memory usage is unavailable"
    }

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            AppLog.memory.error("Activity Monitor not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
