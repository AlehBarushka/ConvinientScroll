import AppKit
import SwiftUI

struct UpdateView: View {
    @ObservedObject var model: UpdateModel
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 12) {
                Text(content.title).font(.headline)
                if let text = content.text {
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .downloading(_, let fraction) = model.state {
                    ProgressView(value: fraction)
                }
                HStack {
                    Spacer()
                    buttons
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var content: (title: String, text: String?) {
        switch model.state {
        case .idle, .checking:
            ("Checking for Updates…", nil)
        case .upToDate(let version):
            ("You're up to date", "Mac Toolkit \(version) is the latest version.")
        case .available(let update):
            ("Mac Toolkit \(update.version) is available", "You have \(model.current).")
        case .downloading(let update, _):
            ("Downloading Mac Toolkit \(update.version)…", nil)
        case .installing:
            ("Installing…", "Mac Toolkit will relaunch in a moment.")
        case .failed(let error, _):
            ("Couldn't update Mac Toolkit", error.message)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.state {
        case .idle, .checking, .downloading:
            Button("Cancel", action: close)
        case .upToDate:
            Button("OK", action: close)
        case .available:
            Button("Not Now", action: close)
            Button("View on GitHub") { model.viewOnGitHub() }
            Button("Install and Relaunch") { model.installUpdate() }
                .keyboardShortcut(.defaultAction)
        case .installing:
            EmptyView()
        case .failed(_, let page):
            if page != nil {
                Button("View on GitHub") { model.viewOnGitHub() }
            }
            Button("OK", action: close)
                .keyboardShortcut(.defaultAction)
        }
    }
}

final class UpdateWindowController: NSObject, NSWindowDelegate {
    private let model: UpdateModel
    private var window: NSWindow?

    init(model: UpdateModel) {
        self.model = model
    }

    func showAndCheck() {
        if window == nil {
            let root = UpdateView(model: model) { [weak self] in self?.window?.close() }
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Software Update"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        model.checkForUpdates()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        model.dismiss()
    }
}
