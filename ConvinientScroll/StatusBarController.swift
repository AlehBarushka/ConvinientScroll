import AppKit
import OSLog
import Combine

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    private var pendingState: IconState?
    private var updateScheduled = false
    private let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    private weak var launchAtLogin: LaunchAtLoginManager?
    private var launchAtLoginMenuItem: NSMenuItem?
    private let onShowShelf: () -> Void
    private let onOpenSettings: () -> Void

    init(
        devicePresence: DevicePresenceMonitor,
        launchAtLogin: LaunchAtLoginManager,
        settings: AppSettings,
        onShowShelf: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.launchAtLogin = launchAtLogin
        self.onShowShelf = onShowShelf
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        let shelfItem = NSMenuItem(title: "Show Shelf", action: #selector(showShelf), keyEquivalent: "")
        shelfItem.target = self
        shelfItem.image = makeSymbol("tray.full")
        menu.addItem(shelfItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Mac Toolkit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        statusItem.menu = menu

        launchAtLoginMenuItem = launchItem
        syncLaunchAtLoginMenuItem()

        settings.$shelfEnabled
            .receive(on: RunLoop.main)
            .sink { shelfItem.isHidden = !$0 }
            .store(in: &cancellables)

        launchAtLogin.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncLaunchAtLoginMenuItem()
            }
            .store(in: &cancellables)

        // The mouse/trackpad icon belongs to the scrolling module; with it off the
        // menu bar shows the shelf tray instead.
        devicePresence.$hasMouse
            .combineLatest(devicePresence.$hasTrackpad, settings.$autoScrollEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] hasMouse, hasTrackpad, showsDevices in
                self?.scheduleIconUpdate(IconState(hasMouse: hasMouse, hasTrackpad: hasTrackpad, showsDevices: showsDevices))
            }
            .store(in: &cancellables)

        scheduleIconUpdate(IconState(
            hasMouse: devicePresence.hasMouse,
            hasTrackpad: devicePresence.hasTrackpad,
            showsDevices: settings.autoScrollEnabled
        ))
    }

    private struct IconState {
        var hasMouse: Bool
        var hasTrackpad: Bool
        var showsDevices: Bool
    }

    @objc private func showShelf() {
        onShowShelf()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    private func syncLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = (launchAtLogin?.isEnabled == true) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        guard let manager = launchAtLogin else { return }
        manager.setEnabled(!manager.isEnabled)
        syncLaunchAtLoginMenuItem()
    }

    private func scheduleIconUpdate(_ state: IconState) {
        pendingState = state
        guard !updateScheduled else { return }
        updateScheduled = true

        // Avoid mutating NSStatusItemView while it is laying out.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            guard let state = self.pendingState else { return }
            self.pendingState = nil
            self.updateIcon(state)
        }
    }

    private func updateIcon(_ state: IconState) {
        let hasMouse = state.hasMouse
        let hasTrackpad = state.hasTrackpad
        // Priority: Mouse > Trackpad. If nothing detected, default to Trackpad.
        let candidates: [String] = if !state.showsDevices {
            ["tray.full", "tray"]
        } else if hasMouse {
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

        // Without any image the item would be invisible and its menu (Quit) unreachable.
        if img == nil {
            AppLog.ui.error("No SF Symbol available for the menu bar icon; showing a text title instead")
            statusItem.button?.imagePosition = .noImage
            statusItem.button?.title = "MT"
        } else {
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.title = ""
        }
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

