import AppKit
import SwiftUI

@MainActor
final class AppsWindowController: NSObject, NSWindowDelegate {
    private let controller: AppsController
    private let settings: AppSettings
    private var window: NSWindow?
    private var model: AppsModel?

    init(controller: AppsController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
    }

    func show(focus bundleID: String?) {
        if window == nil {
            let model = AppsModel(controller: controller, settings: settings)
            let hosting = NSHostingController(rootView: AppsView(model: model, controller: controller))
            hosting.sceneBridgingOptions = [.toolbars]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Apps & Leftovers"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 940, height: 600))
            window.center()
            window.setFrameAutosaveName("AppsWindow")
            self.model = model
            self.window = window
        }
        let controller = controller
        Task { await controller.refreshInstalled() }
        if let bundleID, let model {
            Task { await model.focus(bundleID: bundleID) }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model?.refreshAccess()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        model?.stop()
        model = nil
    }
}
