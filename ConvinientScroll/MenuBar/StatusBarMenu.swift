import AppKit

@MainActor
final class StatusBarMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let modules: [MenuBarModule]
    private let baseItems: [NSMenuItem]
    private let openActivityMonitor: NSMenuItem
    private let moduleSeparator = NSMenuItem.separator()
    private var opened: [MenuBarModule] = []

    init(modules: [MenuBarModule], baseItems: [NSMenuItem], openActivityMonitor: NSMenuItem) {
        self.modules = modules
        self.baseItems = baseItems
        self.openActivityMonitor = openActivityMonitor
        super.init()
        menu.delegate = self
        menu.items = baseItems
    }

    func willOpen() {
        let enabled = modules.filter { $0.segment != nil }
        var items = enabled.flatMap(\.menuItems)
        if !enabled.isEmpty {
            items += [openActivityMonitor, moduleSeparator]
        }
        menu.removeAllItems()
        menu.items = items + baseItems
        opened = enabled
        for module in enabled {
            module.menuWillOpen()
        }
    }

    func didClose() {
        for module in opened {
            module.menuDidClose()
        }
        opened = []
    }

    func menuWillOpen(_ menu: NSMenu) {
        willOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        didClose()
    }
}
