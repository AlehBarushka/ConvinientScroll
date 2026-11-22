import AppKit
import OSLog
import Combine

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()
    private var pendingState: IconState?
    private var shownState: IconState?
    private var updateScheduled = false
    private let symbols = SymbolImageCache()
    private let segmentFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    private let modules: [MenuBarModule]
    private var statusMenu: StatusBarMenu?
    private weak var launchAtLogin: LaunchAtLoginManager?
    private var launchAtLoginMenuItem: NSMenuItem?
    private let onShowShelf: () -> Void
    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void

    init(
        devicePresence: DevicePresenceMonitor,
        launchAtLogin: LaunchAtLoginManager,
        settings: AppSettings,
        modules: [MenuBarModule],
        onShowShelf: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.launchAtLogin = launchAtLogin
        self.modules = modules
        self.onShowShelf = onShowShelf
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        var baseItems: [NSMenuItem] = []
        let shelfItem = NSMenuItem(title: "Show Shelf", action: #selector(showShelf), keyEquivalent: "")
        shelfItem.target = self
        shelfItem.image = makeSymbol("tray.full")
        baseItems.append(shelfItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        baseItems.append(settingsItem)
        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        baseItems.append(updatesItem)
        baseItems.append(.separator())
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        baseItems.append(launchItem)
        baseItems.append(.separator())
        let quitItem = NSMenuItem(title: "Quit Mac Toolkit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        baseItems.append(quitItem)
        let activityItem = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        activityItem.target = self
        let statusMenu = StatusBarMenu(modules: modules, baseItems: baseItems, openActivityMonitor: activityItem)
        self.statusMenu = statusMenu
        statusItem.menu = statusMenu.menu

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

        for module in modules {
            module.onChange = { [weak self] in self?.scheduleIconUpdate(nil) }
        }

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

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            AppLog.ui.error("Activity Monitor not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func showShelf() {
        onShowShelf()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    private func syncLaunchAtLoginMenuItem() {
        launchAtLoginMenuItem?.state = (launchAtLogin?.isEnabled == true) ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        guard let manager = launchAtLogin else { return }
        manager.setEnabled(!manager.isEnabled)
        syncLaunchAtLoginMenuItem()
    }

    private func scheduleIconUpdate(_ state: IconState?) {
        if let state { pendingState = state }
        guard !updateScheduled else { return }
        updateScheduled = true

        // Avoid mutating NSStatusItemView while it is laying out.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            guard let state = self.pendingState ?? self.shownState else { return }
            self.pendingState = nil
            self.shownState = state
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

        guard let button = statusItem.button else { return }
        if button.image !== img {
            button.image = img
        }

        let segments = modules.compactMap(\.segment)
        let title = NSMutableAttributedString()
        // Without any image the item would be invisible and its menu (Quit) unreachable.
        if img == nil {
            AppLog.ui.error("No SF Symbol available for the menu bar icon; showing a text title instead")
            title.append(NSAttributedString(string: "MT", attributes: [.font: segmentFont]))
        }
        title.append(MenuBarTitle.attributedTitle(segments, font: segmentFont) { symbols.image($0, pointSize: 13) })
        button.attributedTitle = title
        button.imagePosition = img == nil ? .noImage : (segments.isEmpty ? .imageOnly : .imageLeading)
        button.setAccessibilityValue(MenuBarTitle.accessibilityValue(segments))
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
        symbols.image(name, pointSize: 14)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
