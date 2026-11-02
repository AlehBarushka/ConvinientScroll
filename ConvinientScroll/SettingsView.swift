//
//  SettingsView.swift
//  ConvinientScroll
//
//  Created by aleh on 23.04.2026.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, scroll, shelf

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .scroll: "Scrolling"
            case .shelf: "File Shelf"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .scroll: "computermouse"
            case .shelf: "tray.full"
            }
        }
    }

    @State private var selection: Section = .general

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selection {
                case .general: GeneralSettings()
                case .scroll: ScrollSettings()
                case .shelf: ShelfSettings()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection.title)
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if let err = launchAtLogin.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Version", value: Self.version)
                LabeledContent("License") {
                    Link("PolyForm Noncommercial 1.0.0", destination: URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!)
                }
                LabeledContent("Copyright", value: "© 2026 Aleh Barushka")
            } footer: {
                Text("Mac Toolkit lives in the menu bar. Turn its modules on or off in the sections on the left. Free for personal and noncommercial use.")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

private struct ScrollSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var devicePresence: DevicePresenceMonitor
    @EnvironmentObject private var naturalScroll: NaturalScrollSettingMonitor

    var body: some View {
        Form {
            Section {
                Toggle("Switch Natural Scrolling automatically", isOn: $settings.autoScrollEnabled)
            } footer: {
                Text("On with a trackpad only, off as soon as a mouse is connected. Nothing changes when neither is found.")
            }

            Section {
                Toggle("Natural Scrolling", isOn: Binding(
                    get: { naturalScroll.isNaturalScrollEnabled },
                    set: { naturalScroll.setEnabled($0, source: .user) }
                ))
                .disabled(!naturalScroll.canWriteSystemPreference)

                if let reason = naturalScroll.writeBlockedReason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Devices") {
                DeviceRow(title: "Mouse", symbol: "computermouse", isConnected: devicePresence.hasMouse)
                DeviceRow(title: "Trackpad", symbol: "rectangle.and.hand.point.up.left", isConnected: devicePresence.hasTrackpad)
            }
        }
    }
}

private struct DeviceRow: View {
    let title: String
    let symbol: String
    let isConnected: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(isConnected ? "Connected" : "Not found")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

private struct ShelfSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ShelfStore

    var body: some View {
        Form {
            Section {
                Toggle("Show the shelf at the top of the screen", isOn: $settings.shelfEnabled)
            } footer: {
                Text("Drag files to the notch, or to the top centre of any display. Hover there later, on any Space, to drag them out again.")
            }

            Section {
                Picker("Keep files for", selection: $settings.shelfRetention) {
                    ForEach(AppSettings.ShelfRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
                LabeledContent("On the shelf") {
                    Text(summary)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ShelfStore.defaultRootURL])
                    }
                    Spacer()
                    Button("Clear Shelf", role: .destructive) {
                        store.removeAll()
                    }
                    .disabled(store.items.isEmpty)
                }
            } footer: {
                Text("Files are cloned, so a copy from the same disk takes no extra space. Files over 1 GB from another disk are kept as a link to the original.")
            }
        }
    }

    private var summary: String {
        let count = store.items.count
        guard count > 0 else { return "Empty" }
        let size = ByteCountFormatter.string(fromByteCount: store.totalSize, countStyle: .file)
        return count == 1 ? "1 file · \(size)" : "\(count) files · \(size)"
    }
}

/// Owns the settings window; the window and its SwiftUI tree are released on close,
/// so an idle app keeps no settings UI in memory.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let services: AppServices
    private var window: NSWindow?

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        // The window shows live state; refresh what is not pushed by notifications.
        services.naturalScroll.refresh()
        services.launchAtLogin.refresh()

        if window == nil {
            let root = SettingsView()
                .environmentObject(services.settings)
                .environmentObject(services.devicePresence)
                .environmentObject(services.naturalScroll)
                .environmentObject(services.launchAtLogin)
                .environmentObject(services.shelfStore)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Mac Toolkit"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 680, height: 460))
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
    }
}
