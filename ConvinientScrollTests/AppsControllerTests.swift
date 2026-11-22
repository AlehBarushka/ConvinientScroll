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
        try sandbox.installApp("Notes", id: "com.example.notes")
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
        try sandbox.installApp("Notes", id: "com.example.notes")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)

        try FileManager.default.removeItem(at: bundle)
        sandbox.watcher.fire()
        await controller.pendingWork?.value
        #expect(controller.installed.map(\.bundleID) == ["com.example.notes"])
        #expect(sandbox.store.loadIndex()?.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.notes"])
        #expect(sandbox.scheduler.checks.count == 1)
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.notes"])
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
        try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let check = try #require(sandbox.scheduler.checks.first)

        controller.watchEnabled = false
        await controller.pendingWork?.value

        #expect(check.cancelled)
        #expect(sandbox.watcher.isWatching == false)
        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.notes"])
    }

    @Test func watchTurnedOffDuringTheSearchDoesNotNotify() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        #expect(sandbox.scheduler.checks.count == 1)
        sandbox.searchHook.beforeSearch = { controller.watchEnabled = false }

        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(sandbox.notices.calls.isEmpty)
    }

    @Test func reinstalledBeforeTheRemovalIsHandledIsNotRecorded() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        #expect(sandbox.scheduler.checks.count == 1)
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        var shown: [[String]] = []
        let subscription = controller.$removed.sink { shown.append($0.map(\.id)) }
        defer { subscription.cancel() }

        sandbox.watcher.fire()
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(controller.installed.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.notes"])
        #expect(shown.allSatisfy { $0.isEmpty })
        #expect(sandbox.notices.calls.isEmpty)
    }

    @Test func pendingCandidatesStayInTheSavedIndex() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.installApp("Notes", id: "com.example.notes")
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        #expect(sandbox.store.loadIndex()?.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.notes"])

        sandbox.scheduler.runPending()
        await controller.pendingWork?.value
        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.notes"])
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
        try sandbox.installApp("Notes", id: "com.example.notes")
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

    @Test func removalSkipsSettingsOfAnAppInstalledSinceTheScan() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        let plist = sandbox.user.appending(path: "Preferences/com.example.foo.plist")
        try sandbox.writeFile(plist, bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let group = try #require(await controller.orphans(hidden: []).first { $0.id == "com.example.foo" })
        let item = try #require(group.items.first)

        try sandbox.installApp("Foo", id: "com.example.foo")
        await controller.refreshInstalled()
        let report = await controller.remove([item])

        #expect(report.removed.isEmpty)
        #expect(report.failed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: plist.path))
    }

    @Test func unchangedIndexIsNotRewritten() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let index = sandbox.store.root.appending(path: "index.json")
        #expect(FileManager.default.fileExists(atPath: index.path))
        try FileManager.default.removeItem(at: index)

        await controller.refreshInstalled()
        sandbox.watcher.fire()
        await controller.pendingWork?.value
        #expect(FileManager.default.fileExists(atPath: index.path) == false)

        try sandbox.installApp("Notes", id: "com.example.notes")
        await controller.refreshInstalled()
        #expect(sandbox.store.loadIndex()?.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.notes"])
    }

    @Test func eventsInsideInstalledBundlesCannotChangeTheList() {
        let installed: Set = ["/Applications/Chatter.app", "/Applications/Utilities/Notes.APP"]
        func check(_ paths: [String]) -> Bool { ApplicationsWatcher.canChangeAppList(paths, installed: installed) }
        #expect(check(["/Applications/"]))
        #expect(check(["/Applications/Chatter.app/Contents/", "/Applications/Utilities/"]))
        #expect(check(["/Applications/Chatter.app"]))
        #expect(check([]))
        #expect(check(["/Applications/Chatter.app/", "/Applications/Utilities/Notes.APP/Contents/Resources/"]) == false)
        #expect(check(["/Applications/Chatter.app/Contents/Helpers/Agent.app/Contents/"]) == false)
        #expect(check(["/Applications/Chatter.app/Contents/", "/Applications/Copying.app/Contents/"]))
        #expect(check(["/Applications/Copying.app/Contents/Info.plist"]))
    }

    @Test func eventInsideANewBundleRescans() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let chatter = try #require(controller.installed.first).path
        let folder = (chatter as NSString).deletingLastPathComponent
        try sandbox.installApp("Notes", id: "com.example.notes")

        sandbox.watcher.fire(["\(chatter)/Contents/"])
        await controller.pendingWork?.value
        #expect(controller.installed.map(\.bundleID) == ["com.example.chatter"])

        sandbox.watcher.fire(["\(folder)/Notes.app/Contents/"])
        await controller.pendingWork?.value
        #expect(controller.installed.map(\.bundleID).sorted() == ["com.example.chatter", "com.example.notes"])
    }

    @Test func failedIndexWriteIsRetried() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.installApp("Chatter", id: "com.example.chatter")
        try sandbox.writeFile(sandbox.store.root, bytes: 1)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        #expect(sandbox.store.loadIndex() == nil)

        try FileManager.default.removeItem(at: sandbox.store.root)
        await controller.refreshInstalled()

        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.chatter"])
    }

    @Test func removalSkipsDataNamedLikeAnInstalledApp() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([])
        let chatter = sandbox.indexedApp("Chatter", id: "com.example.chatter")
        sandbox.store.saveRemoved([RemovedApp(app: chatter, removedAt: Date(timeIntervalSince1970: 0))])
        let support = sandbox.user.appending(path: "Application Support/Chatter")
        try sandbox.writeFile(support.appending(path: "state.db"), bytes: 4096)
        let controller = sandbox.makeController()
        await controller.setEnabled(true)
        let item = try #require(await controller.leftovers(for: chatter).first { $0.match == .name })

        try sandbox.installApp("Chatter", id: "com.example.other", fileName: "Chatter Two")
        await controller.refreshInstalled()
        let report = await controller.remove([item])

        #expect(report.removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: support.path))
    }

    @Test func emptyScanWhileAppsAreKnownIsAFailure() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        sandbox.watcher.fire()
        await controller.pendingWork?.value
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(sandbox.scheduler.checks.isEmpty)
        #expect(controller.removed.isEmpty)
        #expect(sandbox.notices.calls.isEmpty)
        #expect(sandbox.store.loadIndex()?.map(\.bundleID) == ["com.example.chatter"])
    }

    @Test func ownFilesAreNeverOffered() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Toolkit", id: sandbox.ownBundleID)])
        try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/\(sandbox.ownBundleID).plist"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Caches/\(sandbox.ownBundleID).ShipIt/data.bin"), bytes: 4096)
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.old.plist"), bytes: 4096)
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        #expect(sandbox.scheduler.checks.count == 1)
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(controller.removed.isEmpty)
        #expect(sandbox.notices.calls.isEmpty)
        #expect(await controller.orphans(hidden: []).map(\.id) == ["com.example.old"])
    }

    @Test func appMovedElsewhereIsNotRemoved() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let elsewhere = sandbox.root.appending(path: "Elsewhere/Chatter.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        sandbox.locations.urls["com.example.chatter"] = [elsewhere]
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(controller.removed.isEmpty)
        #expect(sandbox.notices.calls.isEmpty)
    }

    @Test func appFoundOnlyInTheTrashIsRemoved() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.saveIndex([sandbox.indexedApp("Chatter", id: "com.example.chatter")])
        try sandbox.installApp("Notes", id: "com.example.notes")
        try sandbox.writeFile(sandbox.user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 4096)
        let trashed = sandbox.trash.appending(path: "Chatter.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trashed, withIntermediateDirectories: true)
        let gone = sandbox.root.appending(path: "Gone/Chatter.app", directoryHint: .isDirectory)
        sandbox.locations.urls["com.example.chatter"] = [trashed, gone]
        let controller = sandbox.makeController()

        await controller.setEnabled(true)
        sandbox.scheduler.runPending()
        await controller.pendingWork?.value

        #expect(controller.removed.map(\.id) == ["com.example.chatter"])
        #expect(sandbox.notices.calls.count == 1)
    }

    @Test func reportSummary() {
        let url = URL(filePath: "/L/Caches/com.example.a")
        let size = ByteCountFormatter.string(fromByteCount: 4096, countStyle: .file)
        #expect(LeftoverNotice.summary(RemovalReport(removed: [url, url], failed: [], adminCancelled: false, bytes: 4096))
            == "Moved 2 items (\(size)) to the Trash")
        #expect(LeftoverNotice.summary(RemovalReport(removed: [url], failed: [url], adminCancelled: false, bytes: 4096))
            == "Moved 1 item (\(size)) to the Trash. 1 item could not be moved.")
        #expect(LeftoverNotice.summary(RemovalReport(removed: [url], failed: [url, url, url], adminCancelled: false, bytes: 4096))
            == "Moved 1 item (\(size)) to the Trash. 3 items could not be moved.")
        #expect(LeftoverNotice.summary(RemovalReport(removed: [url], failed: [url], adminCancelled: true, bytes: 4096))
            == "Moved 1 item to the Trash. Items in /Library were left in place.")
    }

    @Test func noticeTexts() {
        #expect(LeftoverNotice.title(name: "Chatter", size: "2 GB") == "Chatter left 2 GB behind")
        #expect(LeftoverNotice.body(count: 3, hasService: false) == "3 items in Library. Click to review.")
        #expect(LeftoverNotice.body(count: 1, hasService: false) == "1 item in Library. Click to review.")
        #expect(LeftoverNotice.body(count: 2, hasService: true) == "2 items in Library, including a background service. Click to review.")
    }
}
