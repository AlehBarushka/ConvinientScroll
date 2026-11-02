//
//  ConvinientScrollApp.swift
//  ConvinientScroll
//
//  Created by aleh on 23.04.2026.
//

import SwiftUI
import Combine
import UserNotifications
import OSLog

@main
struct ConvinientScrollApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app lives in the menu bar (LSUIElement); its settings window is owned by
        // `SettingsWindowController`, because `showSettingsWindow:` is unreliable from an
        // NSMenu of an agent app. The empty scene only satisfies `App`, and removing its
        // commands keeps ⌘, from opening a blank window.
        Settings { EmptyView() }
            .commandsRemoved()
    }
}

/// Owns the long-lived services. They must start at launch, not when the window
/// appears: a Login Item launch creates no window, so `onAppear` never fires.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let settings = AppSettings()
    let devicePresence = DevicePresenceMonitor()
    let naturalScroll = NaturalScrollSettingMonitor()
    let launchAtLogin = LaunchAtLoginManager()
    private(set) lazy var shelfStore = ShelfStore(
        configuration: .init(rootURL: ShelfStore.defaultRootURL),
        retention: settings.shelfRetention.interval
    )
    private var statusBar: StatusBarController?
    private var autoNaturalScroll: AutoNaturalScrollController?
    private var shelf: ShelfController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    /// Unit tests run inside the app; they must not touch the menu bar or system settings.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func start() {
        guard !Self.isRunningTests else { return }
        AppLog.logLaunchEnvironment()
        NotificationService.shared.requestAuthorizationIfNeeded()
        devicePresence.start()
        naturalScroll.start()
        if autoNaturalScroll == nil {
            let controller = AutoNaturalScrollController()
            controller.start(devicePresence: devicePresence, naturalScroll: naturalScroll, settings: settings)
            autoNaturalScroll = controller
        }

        startShelf()

        if statusBar == nil {
            statusBar = StatusBarController(
                devicePresence: devicePresence,
                launchAtLogin: launchAtLogin,
                settings: settings,
                onShowShelf: { [weak self] in self?.shelf?.showShelf() },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        }
    }

    private func startShelf() {
        guard shelf == nil else { return }
        let store = shelfStore
        Task { await store.load() }

        let controller = ShelfController(store: store)
        shelf = controller

        settings.$shelfRetention
            .removeDuplicates()
            .sink { store.retention = $0.interval }
            .store(in: &cancellables)

        settings.$shelfEnabled
            .removeDuplicates()
            .sink { controller.setEnabled($0) }
            .store(in: &cancellables)
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(services: self)
        }
        settingsWindow?.show()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppServices.shared.start()
    }

    /// Opening the app again from Finder or Spotlight shows its settings, since there is
    /// no Dock icon or window to bring forward otherwise.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppServices.shared.openSettings() }
        return true
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private var didRequest = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !didRequest else { return }
        didRequest = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            // The app still works without notifications; only record why they may be missing.
            if let error {
                AppLog.ui.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                AppLog.ui.info("Notification authorization was not granted")
            }
        }
    }

    func showNaturalScrollChanged(enabled: Bool, applied: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Natural Scroll"
        let state = enabled ? "Enabled" : "Disabled"
        content.body = applied ? state : "\(state) (not applied)"

        let request = UNNotificationRequest(
            identifier: "convinientscroll-changed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.ui.error("Cannot deliver notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Ensure banners show even while app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
