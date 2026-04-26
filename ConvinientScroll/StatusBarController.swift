import AppKit
import Combine

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    private var pendingState: (hasMouse: Bool, hasTrackpad: Bool)?
    private var updateScheduled = false
    private let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    private weak var launchAtLogin: LaunchAtLoginManager?
    private var launchAtLoginMenuItem: NSMenuItem?

    init(devicePresence: DevicePresenceMonitor, launchAtLogin: LaunchAtLoginManager) {
        self.launchAtLogin = launchAtLogin
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu

        launchAtLoginMenuItem = launchItem
        syncLaunchAtLoginMenuItem()

        launchAtLogin.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncLaunchAtLoginMenuItem()
            }
            .store(in: &cancellables)

        devicePresence.$hasMouse
            .combineLatest(devicePresence.$hasTrackpad)
            .receive(on: RunLoop.main)
            .sink { [weak self] hasMouse, hasTrackpad in
                self?.scheduleIconUpdate(hasMouse: hasMouse, hasTrackpad: hasTrackpad)
            }
            .store(in: &cancellables)

        scheduleIconUpdate(hasMouse: devicePresence.hasMouse, hasTrackpad: devicePresence.hasTrackpad)
    }

    private func syncLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = (launchAtLogin?.isEnabled == true) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        guard let manager = launchAtLogin else { return }
        manager.setEnabled(!manager.isEnabled)
        syncLaunchAtLoginMenuItem()
    }

    private func scheduleIconUpdate(hasMouse: Bool, hasTrackpad: Bool) {
        pendingState = (hasMouse: hasMouse, hasTrackpad: hasTrackpad)
        guard !updateScheduled else { return }
        updateScheduled = true

        // Avoid mutating NSStatusItemView while it is laying out.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            guard let state = self.pendingState else { return }
            self.pendingState = nil
            self.updateIcon(hasMouse: state.hasMouse, hasTrackpad: state.hasTrackpad)
        }
    }

    private func updateIcon(hasMouse: Bool, hasTrackpad: Bool) {
        // Priority: Mouse > Trackpad. If nothing detected, default to Trackpad.
        let candidates: [String] = if hasMouse {
            // Older macOS may not have "mouse"
            ["computermouse", "mouse", "cursorarrow"]
        } else if hasTrackpad || (!hasMouse && !hasTrackpad) {
            // Older macOS may not have "trackpad.2"
            ["trackpad", "trackpad.2", "rectangle.and.hand.point.up.left"]
        } else {
            ["questionmark.circle"]
        }

        let img = makeFirstAvailableSymbol(candidates)
            ?? makeSymbol("questionmark.circle")

        img?.isTemplate = true
        statusItem.button?.image = img
    }

    private func makeFirstAvailableSymbol(_ names: [String]) -> NSImage? {
        for name in names {
            if let img = makeSymbol(name) {
                return img
            }
        }
        return nil
    }

    private func makeSymbol(_ name: String) -> NSImage? {
        // Some symbols may be unavailable depending on macOS version.
        if let configured = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            return configured
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

