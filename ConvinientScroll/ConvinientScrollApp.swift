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
    private var memory: MemoryController?
    private var thermal: ThermalController?
    private var apps: AppsController?
    private var appsWindow: AppsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var updateWindow: UpdateWindowController?
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
        startMemory()
        startThermal()
        startApps()
        reportPreviousUpdate()

        if statusBar == nil {
            statusBar = StatusBarController(
                devicePresence: devicePresence,
                launchAtLogin: launchAtLogin,
                settings: settings,
                modules: [memory as MenuBarModule?, thermal].compactMap { $0 },
                onShowShelf: { [weak self] in self?.shelf?.showShelf() },
                onOpenApps: { [weak self] in self?.openApps() },
                onOpenSettings: { [weak self] in self?.openSettings() },
                onCheckForUpdates: { [weak self] in self?.checkForUpdates() }
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

    private func startMemory() {
        guard memory == nil else { return }
        let controller = MemoryController()
        memory = controller
        settings.$memoryEnabled
            .removeDuplicates()
            .sink { controller.setEnabled($0) }
            .store(in: &cancellables)
    }

    private func startThermal() {
        guard thermal == nil else { return }
        let controller = ThermalController()
        thermal = controller
        settings.$thermalAlertsEnabled
            .removeDuplicates()
            .sink { controller.alertsEnabled = $0 }
            .store(in: &cancellables)
        settings.$thermalEnabled
            .removeDuplicates()
            .sink { controller.setEnabled($0) }
            .store(in: &cancellables)
    }

    private func startApps() {
        guard apps == nil else { return }
        let controller = AppsController(environment: .live())
        apps = controller
        NotificationService.shared.onOpenLeftovers = { [weak self] in self?.openApps(focus: $0) }
        settings.$appsWatchEnabled
            .removeDuplicates()
            .sink { controller.watchEnabled = $0 }
            .store(in: &cancellables)
        settings.$appsEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if !enabled { self?.appsWindow?.close() }
                Task { await controller.setEnabled(enabled) }
            }
            .store(in: &cancellables)
    }

    func openApps(focus: String? = nil) {
        guard let apps, settings.appsEnabled else { return }
        if appsWindow == nil {
            appsWindow = AppsWindowController(controller: apps, settings: settings)
        }
        appsWindow?.show(focus: focus)
    }

    private func reportPreviousUpdate() {
        guard let current = AppVersion.current else {
            AppLog.updates.error("Cannot read the app version; skipping the update report")
            return
        }
        UpdateLaunchReport.run(
            store: PendingUpdateStore(defaults: .standard),
            failureFile: PendingUpdateStore.failureFileURL,
            current: current,
            isLoginItemEnabled: { [launchAtLogin] in launchAtLogin.isEnabled },
            enableLoginItem: { [launchAtLogin] in launchAtLogin.setEnabled(true) },
            showAlert: { title, text in
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = text
                alert.addButton(withTitle: "OK")
                NSApp.activate()
                alert.runModal()
            }
        )
    }

    func checkForUpdates() {
        if updateWindow == nil {
            updateWindow = UpdateWindowController(model: makeUpdateModel())
        }
        updateWindow?.showAndCheck()
    }

    private func makeUpdateModel() -> UpdateModel {
        guard let current = AppVersion.current else {
            return UpdateModel(
                current: AppVersion("0")!,
                check: { () async throws(UpdateError) -> UpdateCheckResult in throw .unreadableVersion(tag: "?") },
                install: { (_, _) async throws(UpdateError) in },
                openURL: { _ in }
            )
        }
        let launchAtLogin = launchAtLogin
        return UpdateModel(
            current: current,
            check: { () async throws(UpdateError) -> UpdateCheckResult in
                try await ReleaseFeed.live().check(current: current)
            },
            install: { (update, progress) async throws(UpdateError) in
                try await UpdateInstaller(environment: .live(launchAtLogin: launchAtLogin))
                    .install(update, progress: progress)
            },
            openURL: { NSWorkspace.shared.open($0) }
        )
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
    var onOpenLeftovers: ((String) -> Void)?
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

    func showThrottling(_ alert: ThrottleAlert) {
        let content = UNMutableNotificationContent()
        let identifier: String
        switch alert {
        case .heavy:
            identifier = "thermal-heavy"
            content.title = "Mac is throttling"
            content.body = "Thermal pressure is Heavy. macOS is slowing the CPU to cool down."
        case .critical:
            identifier = "thermal-critical"
            content.title = "Mac is throttling heavily"
            content.body = "Thermal pressure is Critical. Performance is strongly reduced."
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.thermal.error("Cannot deliver notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func showLeftovers(bundleID: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["bundleID": bundleID]

        let request = UNNotificationRequest(identifier: "apps-leftovers-\(bundleID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.apps.error("Cannot deliver notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let bundleID = response.notification.request.content.userInfo["bundleID"] as? String
        completionHandler()
        guard let bundleID else { return }
        Task { @MainActor in
            self.onOpenLeftovers?(bundleID)
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
