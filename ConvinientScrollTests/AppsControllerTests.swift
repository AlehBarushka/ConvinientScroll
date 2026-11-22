import Combine
import Foundation
import Testing
@testable import MacToolkit

@MainActor @Suite("AppsController") struct AppsControllerTests {
    @Test func firstRunFlagsNothing() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.installApp("Editor", id: "com.example.editor")
        let controller = sandbox.makeController()

        await controller.setEnabled(true)

        #expect(sandbox.scheduler.checks.isEmpty)
        #expect(controller.removed.isEmpty)
        #expect(controller.installed.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.editor"])
        #expect(sandbox.store.loadIndex()?.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.editor"])
        #expect(sandbox.watcher.folders == [sandbox.apps])
    }

    @Test func removalWithLeftoversNotifies() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        let plist = sandbox.user.appending(path: "Preferences/com.example.chatter.plist")
        try sandbox.writeFile(plist, bytes: 4096)
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        #expect(sandbox.scheduler.checks.count == 1)
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(controller.removed.map(\.app.bundleID) == ["com.example.chatter"])
        #expect(controller.removed.map(\.removedAt) == [Date(timeIntervalSince1970: 1_000)])
        #expect(sandbox.store.loadRemoved().map(\.app.bundleID) == ["com.example.chatter"])
        let size = ByteCountFormatter.string(fromByteCount: LibraryScanner.size(of: plist), countStyle: .file)
        #expect(sandbox.notices.calls == [Notice(
            bundleID: "com.example.chatter",
            title: LeftoverNotice.title(name: "Chatter", size: size),
            body: "1 item in Library. Click to review.")])
    }

    @Test func removalWithoutLeftoversIsSilent() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let bundle = try sandbox.installApp("Chatter", id: "com.example.chatter")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)

        try FileManager.default.removeItem(at: bundle)
        sandbox.watcher.fire()
        await controller.pendingWork?.value
        #expect(controller.installed.isEmpty)
        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.chatter"])
        #expect(sandbox.scheduler.checks.count == 1)
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(sandbox.store.loadIndex()?.isEmpty == true)
        #expect(sandbox.notices.calls.isEmpty)
        #expect(controller.removed.isEmpty)
        #expect(sandbox.store.loadRemoved().isEmpty)
    }

    @Test func watchOffRecordsNothing() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        controller.watchEnabled = false

        await controller.setEnabled(true)
        await controller.refreshInstalled()
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(sandbox.watcher.isWatching == false)
        #expect(sandbox.scheduler.checks.isEmpty)
        #expect(controller.removed.isEmpty)
        #expect(sandbox.notices.calls.isEmpty)
        #expect(sandbox.store.loadIndex()?.isEmpty == true)
    }

    @Test func turningWatchOffCancelsPendingChecks() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let check = try #require(sandbox.scheduler.checks.first)

        controller.watchEnabled = false
        await controller.pendingWork?.value

        #expect(check.cancelled)
        #expect(sandbox.watcher.isWatching == false)
        #expect(sandbox.store.loadIndex()?.isEmpty == true)
    }

    @Test func watchTurnedOffDuringTheSearchDoesNotNotify() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        sandbox.searchHook.beforeSearch = { controller.watchEnabled = false }

        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(sandbox.notices.calls.isEmpty)
    }

    @Test func reinstalledBeforeTheRemovalIsHandledIsNotRecorded() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        var shown: [[String]] = []
        let subscription = controller.$removed.sink { shown.append($0.map(\.id)) }
        defer { subscription.cancel() }

        sandbox.watcher.fire()
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(controller.installed.map(\.bundleID) == ["com.example.chatter"])
        #expect(shown.allSatisfy { $0.isEmpty })
        #expect(sandbox.notices.calls.isEmpty)
    }

    @Test func pendingCandidatesStayInTheSavedIndex() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.chatter"])

        sandbox.scheduler.runPending()
        await controller.pendingWork?.value
        #expect(sandbox.store.loadIndex()?.isEmpty == true)
    }

    @Test func turningWatchOnIgnoresAppsRemovedWhileOff() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        let bundle = try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        controller.watchEnabled = false
        await controller.setEnabled(true)
        try FileManager.default.removeItem(at: bundle)

        controller.watchEnabled = true
        await controller.pendingWork?.value
        sandbox.watcher.fire()
        await controller.pendingWork?.value

        #expect(sandbox.watcher.isWatching)
        #expect(sandbox.scheduler.checks.isEmpty)
        #expect(controller.removed.isEmpty)
    }

    @Test func disablingStopsWatcherAndChecks() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let check = try #require(sandbox.scheduler.checks.first)

        await controller.setEnabled(false)

        #expect(check.cancelled)
        #expect(sandbox.watcher.isWatching == false)
    }

    @Test func reinstallDropsTheRemovedEntry() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        let chatter = sandbox.indexedApp("Chatter", id: "com.example.chatter")
        sandbox.store.saveRemoved([RemovedApp(app: chatter, removedAt: Date(timeIntervalSince1970: 0))])
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        #expect(controller.removed.map(\.app.bundleID) == ["com.example.chatter"])

        try sandbox.installApp("Chatter", id: "com.example.chatter")
        await controller.refreshInstalled()

        #expect(controller.removed.isEmpty)
        #expect(sandbox.store.loadRemoved().isEmpty)
    }

    @Test func keepDropsTheEntryAndLeavesFiles() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        let chatter = sandbox.indexedApp("Chatter", id: "com.example.chatter")
        sandbox.store.saveRemoved([RemovedApp(app: chatter, removedAt: Date(timeIntervalSince1970: 0))])
        let plist = sandbox.user.appending(path: "Preferences/com.example.chatter.plist")
        try sandbox.writeFile(plist, bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)

        controller.keep(try #require(controller.removed.first))

        #expect(controller.removed.isEmpty)
        #expect(sandbox.store.loadRemoved().isEmpty)
        #expect(FileManager.default.fileExists(atPath: plist.path))
    }

    @Test func removingEveryLeftoverDropsTheEntry() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        let chatter = sandbox.indexedApp("Chatter", id: "com.example.chatter")
        sandbox.store.saveRemoved([RemovedApp(app: chatter, removedAt: Date(timeIntervalSince1970: 0))])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/com.example.chatter/data.bin"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let items = await controller.leftovers(for: chatter)
        #expect(items.count == 2)

        let partial = await controller.remove(Array(items.prefix(1)))
        #expect(partial.removed == [items[0].id])
        #expect(controller.removed.map(\.app.bundleID) == ["com.example.chatter"])

        let rest = await controller.remove(Array(items.dropFirst()))
        #expect(rest.removed == [items[1].id])
        #expect(controller.removed.isEmpty)
        #expect(sandbox.store.loadRemoved().isEmpty)
    }

    @Test func noticeTexts() {
        #expect(LeftoverNotice.title(name: "Chatter", size: "2 GB") == "Chatter left 2 GB behind")
        #expect(LeftoverNotice.body(count: 3, hasService: false) == "3 items in Library. Click to review.")
        #expect(LeftoverNotice.body(count: 1, hasService: false) == "1 item in Library. Click to review.")
        #expect(LeftoverNotice.body(count: 2, hasService: true) == "2 items in Library, including a background service. Click to review.")
    }
}
