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

        model.query = "Chatter"
        await model.loadSizes()
        model.query = "Notes"
        await model.loadSizes()
        model.query = ""
        #expect(model.rows.map(\.title) == ["Alpha", "Chatter", "Notes"])
        #expect(model.rows.map(\.size).map { $0 == nil } == [true, false, false])

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
}
