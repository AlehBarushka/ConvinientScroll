import Foundation
import Testing
@testable import MacToolkit

@MainActor @Suite("AppsModel") struct AppsModelTests {
    private func freshSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "AppsModelTests-\(UUID().uuidString)")!)
    }

    private func removedChatter(_ sandbox: Sandbox) throws -> InstalledApp {
        sandbox.store.saveIndex([])
        let chatter = sandbox.indexedApp("Chatter", id: "com.example.chatter")
        sandbox.store.saveRemoved([RemovedApp(app: chatter, removedAt: Date(timeIntervalSince1970: 0))])
        return chatter
    }

    @Test func appsDefaults() {
        let settings = freshSettings()

        #expect(settings.appsEnabled == true)
        #expect(settings.appsWatchEnabled == true)
        #expect(settings.appsHiddenIDs == [])
    }

    @Test func nameMatchesStartUnchecked() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        _ = try removedChatter(sandbox)
        let plist = sandbox.user.appending(path: "Preferences/com.example.chatter.plist")
        let support = sandbox.user.appending(path: "Application Support/Chatter/state.db")
        try sandbox.writeFile(plist, bytes: 4096)
        try sandbox.writeFile(support, bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .removed

        await model.select("com.example.chatter")

        #expect(model.items.count == 2)
        #expect(model.checked.map(\.lastPathComponent) == [plist.lastPathComponent])
    }

    @Test func runningAppCannotClean() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/com.example.chatter/data.bin"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())

        await model.select(try #require(controller.installed.first).path)
        #expect(model.canClean)

        sandbox.running.ids = ["com.example.chatter"]
        #expect(model.canClean == false)
    }

    @Test func cleanableIsOnlyCachesAndLogs() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/com.example.chatter/data.bin"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Logs/com.example.chatter/run.log"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Application Support/com.example.chatter/data.db"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())

        await model.select(try #require(controller.installed.first).path)

        #expect(model.items.count == 4)
        #expect(Set(model.cleanableItems().map(\.kind)) == [.cache, .log])
        #expect(model.checked.isEmpty)
    }

    @Test func sortAndFilter() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let chatter = try sandbox.installApp("Chatter", id: "com.example.chatter")
        let notes = try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.installApp("Alpha", id: "com.example.alpha")
        try sandbox.writeFile(chatter.appending(path: "Contents/Resources/data.bin"), bytes: 50_000)
        try sandbox.writeFile(notes.appending(path: "Contents/Resources/data.bin"), bytes: 500_000)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())

        model.query = "chat"
        #expect(model.rows.map(\.title) == ["Chatter"])

        model.query = ""
        await model.loadSizes()
        #expect(model.rows.map(\.title) == ["Alpha", "Chatter", "Notes"])
        #expect(model.rows.allSatisfy { $0.size != nil })

        model.sort = .size
        #expect(model.rows.map(\.title) == ["Notes", "Chatter", "Alpha"])
    }

    @Test func selectionMovesAfterRemoval() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.a.plist"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/com.example.a/data.bin"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.b.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .orphans
        await model.scanOrphans()
        #expect(model.rows.map(\.id) == ["com.example.a", "com.example.b"])

        await model.select("com.example.a")
        #expect(model.checked.count == 2)
        model.askToTrashChecked()
        #expect(model.pendingRemoval?.count == 2)
        await model.confirmRemoval()

        #expect(model.pendingRemoval == nil)
        #expect(model.lastReport?.removed.count == 2)
        #expect(model.rows.map(\.id) == ["com.example.b"])
        #expect(model.selectedID == "com.example.b")
        #expect(model.items.count == 1)
    }

    @Test func hideAndUnhide() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.a.plist"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.b.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let settings = freshSettings()
        let model = AppsModel(controller: controller, settings: settings)
        model.section = .orphans
        await model.scanOrphans()
        await model.select("com.example.a")

        model.hideSelected()

        #expect(settings.appsHiddenIDs == ["com.example.a"])
        #expect(model.orphans?.map(\.id) == ["com.example.b"])

        model.unhide("com.example.a")
        #expect(settings.appsHiddenIDs.isEmpty)
    }

    @Test func unsizedRowsSortLast() {
        let rows = [
            AppsRow(id: "a", title: "A", subtitle: "", size: nil),
            AppsRow(id: "b", title: "B", subtitle: "", size: 10),
            AppsRow(id: "c", title: "C", subtitle: "", size: 20)
        ]

        #expect(AppsModel.sorted(rows, by: .size).map(\.id) == ["c", "b", "a"])
    }

    @Test func installedSearchIgnoresThePath() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.installApp("Notes", id: "com.example.notes")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())

        model.query = "Applications"
        #expect(model.rows.isEmpty)
        model.query = "example.notes"
        #expect(model.rows.map(\.title) == ["Notes"])
    }

    @Test func askToCleanTakesOnlyCachesAndLogs() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/com.example.chatter/data.bin"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Logs/com.example.chatter/run.log"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        await model.select(try #require(controller.installed.first).path)

        model.askToClean()
        #expect(Set(try #require(model.pendingRemoval).map(\.kind)) == [.cache, .log])

        model.pendingRemoval = nil
        sandbox.running.ids = ["com.example.chatter"]
        model.askToClean()
        #expect(model.pendingRemoval == nil)
    }

    @Test func installedRefusesToTrashCheckedItems() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        let plist = sandbox.user.appending(path: "Preferences/com.example.chatter.plist")
        try sandbox.writeFile(plist, bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        await model.select(try #require(controller.installed.first).path)
        model.checked = Set(model.items.map(\.id))

        model.askToTrashChecked()
        #expect(model.pendingRemoval == nil)

        model.pendingRemoval = model.items
        await model.confirmRemoval()
        #expect(FileManager.default.fileExists(atPath: plist.path))
        #expect(model.lastReport == nil)
    }

    @Test func confirmationOfARunningAppRemovesNothing() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        let cache = sandbox.user.appending(path: "Caches/com.example.chatter/data.bin")
        try sandbox.writeFile(cache, bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        await model.select(try #require(controller.installed.first).path)
        model.askToClean()
        sandbox.running.ids = ["com.example.chatter"]

        await model.confirmRemoval()

        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(model.lastReport == nil)
    }

    @Test func reinstalledAppLeavesTheRemovedSelection() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        _ = try removedChatter(sandbox)
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .removed
        await model.select("com.example.chatter")
        #expect(model.checked.count == 1)

        try sandbox.installApp("Chatter", id: "com.example.chatter")
        await controller.refreshInstalled()
        await model.pendingSync?.value

        #expect(model.selectedID == nil)
        #expect(model.items.isEmpty)
        #expect(model.checked.isEmpty)
    }

    @Test func deletedInstalledAppLeavesTheSelection() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let bundle = try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.installApp("Notes", id: "com.example.notes")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        await model.select(try #require(controller.installed.first { $0.name == "Chatter" }).path)

        try FileManager.default.removeItem(at: bundle)
        await controller.refreshInstalled()
        await model.pendingSync?.value
        await model.pendingLoad?.value

        #expect(model.selectedID == controller.installed.first?.path)
        #expect(model.rows.map(\.title) == ["Notes"])
    }

    @Test func sizesDoNotLeakBetweenSections() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        let chatter = sandbox.indexedApp("Chatter", id: "com.example.chatter")
        sandbox.store.saveRemoved([RemovedApp(app: chatter, removedAt: Date(timeIntervalSince1970: 0))])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 500_000)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .removed
        await model.loadSizes()
        #expect(model.rows.first?.size != nil)

        model.section = .orphans
        await model.scanOrphans()

        #expect(model.rows.map(\.id) == ["com.example.chatter"])
        #expect(model.rows.first?.size == nil)
        model.section = .removed
        #expect(model.rows.first?.size != nil)
    }

    @Test func sizesAreRecomputedAfterRemoval() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.a.plist"), bytes: 500_000)
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/com.example.a/data.bin"), bytes: 500_000)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .orphans
        await model.scanOrphans()
        await model.loadSizes()
        let full = try #require(model.rows.first?.size)
        await model.select("com.example.a")
        model.checked = model.checked.filter { $0.lastPathComponent == "com.example.a.plist" }
        model.askToTrashChecked()

        await model.confirmRemoval()

        let rest = try #require(model.rows.first?.size)
        #expect(rest < full)
        #expect(model.isRemoving == false)
    }

    @Test func switchingSectionDuringRemovalKeepsTheNewSelection() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.a.plist"), bytes: 4096)
        try sandbox.installApp("Notes", id: "com.example.notes")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .orphans
        await model.scanOrphans()
        await model.select("com.example.a")
        model.askToTrashChecked()

        let removal = Task { await model.confirmRemoval() }
        await Task.yield()
        model.section = .installed
        let notes = try #require(controller.installed.first).path
        await model.select(notes)
        await removal.value

        #expect(model.section == .installed)
        #expect(model.selectedID == notes)
        #expect(model.orphans?.isEmpty == true)
    }

    @Test func gainingAccessReloadsTheSelectedRow() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        _ = try removedChatter(sandbox)
        try sandbox.writeFile(sandbox.user.appending(path: "Containers/com.example.chatter/data.db"), bytes: 4096)
        sandbox.access.granted = false
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        model.section = .removed
        await model.select("com.example.chatter")
        #expect(model.items.map(\.isAccessible) == [false])
        #expect(model.hasFullDiskAccess == false)

        sandbox.access.granted = true
        model.refreshAccess()
        await model.pendingLoad?.value

        #expect(model.hasFullDiskAccess)
        #expect(model.items.map(\.isAccessible) == [true])
    }

    @Test func cancellingLoadSizesStopsSizeWork() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        for name in ["Alpha", "Bravo", "Charlie"] {
            try sandbox.installApp(name, id: "com.example.\(name.lowercased())")
        }
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        var searches = 0
        var sizing: Task<Void, Never>?
        sandbox.searchHook.beforeSearch = {
            searches += 1
            sizing?.cancel()
        }

        sizing = Task { await model.loadSizes() }
        await sizing?.value

        #expect(searches == 1)
    }

    @Test func stoppedModelIgnoresControllerChanges() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Alpha", id: "com.example.alpha")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let model = AppsModel(controller: controller, settings: freshSettings())
        await model.loadSizes()
        var searches = 0
        sandbox.searchHook.beforeSearch = { searches += 1 }

        model.stop()
        try sandbox.installApp("Bravo", id: "com.example.bravo")
        await controller.refreshInstalled()
        await model.pendingSync?.value
        await model.loadSizes()

        #expect(controller.installed.count == 2)
        #expect(searches == 0)
    }

    @Test func firstRowIsSelectedWhenRowsAppear() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Alpha", id: "com.example.alpha")
        let controller = sandbox.makeController()
        let model = AppsModel(controller: controller, settings: freshSettings())
        #expect(model.rows.isEmpty)

        await controller.setEnabled(true)
        await model.pendingSync?.value

        #expect(model.selectedID == controller.installed.first?.path)
    }
}
