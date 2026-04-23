//
//  natural_scrollApp.swift
//  natural-scroll
//
//  Created by aleh on 23.04.2026.
//

import SwiftUI

@main
struct natural_scrollApp: App {
    @StateObject private var devicePresence = DevicePresenceMonitor()
    @StateObject private var naturalScroll = NaturalScrollSettingMonitor()
    @State private var statusBar: StatusBarController?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(devicePresence)
                .environmentObject(naturalScroll)
                .onAppear {
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
