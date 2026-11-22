import AppKit
import Testing
@testable import MacToolkit

@MainActor
private final class FakeModule: MenuBarModule {
    var segment: MenuBarSegment?
    var menuItems: [NSMenuItem]
    var onChange: (() -> Void)?
    var opened = 0
    var closed = 0

    init(enabled: Bool, rows: [String]) {
        segment = enabled ? MenuBarSegment(symbol: "x", text: "1", reservedCharacters: 1, tint: .none, accessibility: "") : nil
        menuItems = rows.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") }
    }

    func menuWillOpen() { opened += 1 }
    func menuDidClose() { closed += 1 }
}

@Suite("StatusBarMenu")
@MainActor
struct StatusBarMenuTests {
    private let base = ["Show Shelf", "Settings…", "Quit Mac Toolkit"]

    private func makeMenu(_ modules: [MenuBarModule]) -> StatusBarMenu {
        StatusBarMenu(
            modules: modules,
            baseItems: base.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") },
            openActivityMonitor: NSMenuItem(title: "Open Activity Monitor", action: nil, keyEquivalent: "")
        )
    }

    @Test func modulesOffKeepsBaseMenu() {
        let menu = makeMenu([FakeModule(enabled: false, rows: ["Mem"]), FakeModule(enabled: false, rows: ["CPU"])])
        menu.willOpen()
        #expect(menu.menu.items.map(\.title) == base)
    }

    @Test func moduleRowsGoFirst() {
        let menu = makeMenu([FakeModule(enabled: true, rows: ["Mem"]), FakeModule(enabled: true, rows: ["CPU", "Thr"])])
        menu.willOpen()
        let items = menu.menu.items
        #expect(items.prefix(4).map(\.title) == ["Mem", "CPU", "Thr", "Open Activity Monitor"])
        #expect(items[4].isSeparatorItem)
        #expect(items.dropFirst(5).map(\.title) == base)
    }

    @Test func activityMonitorOnceForTwoModules() {
        let menu = makeMenu([FakeModule(enabled: true, rows: ["Mem"]), FakeModule(enabled: true, rows: ["CPU"])])
        menu.willOpen()
        #expect(menu.menu.items.filter { $0.title == "Open Activity Monitor" }.count == 1)
    }

    @Test func reopenDoesNotDuplicate() {
        let menu = makeMenu([FakeModule(enabled: true, rows: ["Mem"]), FakeModule(enabled: false, rows: ["CPU"])])
        menu.willOpen()
        let count = menu.menu.items.count
        menu.didClose()
        menu.willOpen()
        #expect(menu.menu.items.count == count)
    }

    @Test func hooksReachOnlyEnabledModules() {
        let on = FakeModule(enabled: true, rows: ["Mem"])
        let off = FakeModule(enabled: false, rows: ["CPU"])
        let menu = makeMenu([on, off])
        menu.willOpen()
        menu.didClose()
        #expect((on.opened, on.closed) == (1, 1))
        #expect((off.opened, off.closed) == (0, 0))
    }

    @Test func closeReachesModulesThatOpened() {
        let module = FakeModule(enabled: true, rows: ["CPU"])
        let menu = makeMenu([module])
        menu.willOpen()
        module.segment = nil
        menu.didClose()
        #expect(module.closed == 1)
    }
}
