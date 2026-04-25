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
    @StateObject private var devicePresence = DevicePresenceMonitor()
    @StateObject private var naturalScroll = NaturalScrollSettingMonitor()
    @State private var statusBar: StatusBarController?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(devicePresence)
                .environmentObject(naturalScroll)
                .onAppear {
                    NotificationService.shared.requestAuthorizationIfNeeded()
                    devicePresence.start()
                    naturalScroll.start()
                    if statusBar == nil {
                        statusBar = StatusBarController(devicePresence: devicePresence)
                    }
                }
        }
        .windowResizability(.contentSize)
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
