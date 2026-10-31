//
//  ConvinientScrollApp.swift
//  ConvinientScroll
//
//  Created by aleh on 23.04.2026.
//

import SwiftUI
import UserNotifications

@main
struct ConvinientScrollApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(services.devicePresence)
                .environmentObject(services.naturalScroll)
                .environmentObject(services.launchAtLogin)
        }
        .windowResizability(.contentSize)
    }
}

/// Owns the long-lived services. They must start at launch, not when the window
/// appears: a Login Item launch creates no window, so `onAppear` never fires.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let devicePresence = DevicePresenceMonitor()
    let naturalScroll = NaturalScrollSettingMonitor()
    let launchAtLogin = LaunchAtLoginManager()
    private var statusBar: StatusBarController?
    private var autoNaturalScroll: AutoNaturalScrollController?

    func start() {
        NotificationService.shared.requestAuthorizationIfNeeded()
        devicePresence.start()
        naturalScroll.start()
        if statusBar == nil {
            statusBar = StatusBarController(devicePresence: devicePresence, launchAtLogin: launchAtLogin)
        }
        if autoNaturalScroll == nil {
            let controller = AutoNaturalScrollController()
            controller.start(devicePresence: devicePresence, naturalScroll: naturalScroll)
            autoNaturalScroll = controller
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppServices.shared.start()
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Intentionally ignore result; app still works without notifications.
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

        UNUserNotificationCenter.current().add(request)
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
