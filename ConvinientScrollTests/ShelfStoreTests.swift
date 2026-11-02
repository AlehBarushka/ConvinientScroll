import Foundation
import Testing
@testable import MacToolkit

@MainActor
@Suite("ShelfStore")
struct ShelfStoreTests {
    /// A temporary folder with a source area and a shelf root; removed on deinit of the test.
    @MainActor
    final class Sandbox {
        let base: URL
        var root: URL { base.appending(path: "Shelf", directoryHint: .isDirectory) }
        var sources: URL { base.appending(path: "Sources", directoryHint: .isDirectory) }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            base = FileManager.default.temporaryDirectory
                .appending(path: "ShelfStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: base) }

        func file(_ name: String, bytes: Int = 16, in folder: String? = nil) throws -> URL {
            var dir = sources
            if let folder { dir = dir.appending(path: folder, directoryHint: .isDirectory) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: name)
            try Data(repeating: 0x2A, count: bytes).write(to: url)
            return url
        }

        func store(
            threshold: Int64 = 1 << 30,
            sameVolume: Bool = true,
            retention: TimeInterval = 3600
        ) -> ShelfStore {
            ShelfStore(
                configuration: .init(
                    rootURL: root,
                    referenceThreshold: threshold,
                    isSameVolume: { _, _ in sameVolume },
                    schedulesPurge: false
                ),
                retention: retention,
                now: { [unowned self] in self.clock }
            )
        }

        func itemFolders() -> [String] {
            let items = root.appending(path: "items", directoryHint: .isDirectory)
            return ((try? FileManager.default.contentsOfDirectory(atPath: items.path)) ?? []).sorted()
        }
    }

    @Test func copiesAFile() async throws {
        let box = try Sandbox()
        let source = try box.file("invoice.pdf", bytes: 128)
        let store = box.store()

        let added = await store.add([source])

        let item = try #require(added.first)
        #expect(store.items == [item])
        #expect(!item.isReference)
        #expect(item.byteSize == 128)
        let copy = try #require(store.url(for: item))
        #expect(copy != source)
        #expect(try Data(contentsOf: copy) == Data(contentsOf: source))

        // The copy is independent of the original.
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func copiesAFolderWithItsContents() async throws {
        let box = try Sandbox()
        _ = try box.file("a.txt", bytes: 10, in: "Project")
        _ = try box.file("b.txt", bytes: 20, in: "Project/nested")
        let store = box.store()

        let item = try #require(await store.add([box.sources.appending(path: "Project")]).first)

        #expect(item.isDirectory)
        #expect(item.byteSize == 30)
        let copy = try #require(store.url(for: item))
        #expect(FileManager.default.fileExists(atPath: copy.appending(path: "nested/b.txt").path))
    }

    @Test func keepsFilesWithTheSameNameApart() async throws {
        let box = try Sandbox()
        let first = try box.file("photo.png", bytes: 1, in: "one")
        let second = try box.file("photo.png", bytes: 2, in: "two")
        let store = box.store()

        let added = await store.add([first, second])

        #expect(added.count == 2)
        let urls = added.compactMap { store.url(for: $0) }
        #expect(Set(urls).count == 2)
        #expect(try Data(contentsOf: urls[1]).count == 2)
    }

    @Test func linksALargeFileFromAnotherVolume() async throws {
        let box = try Sandbox()
        let source = try box.file("movie.mov", bytes: 100)
        let store = box.store(threshold: 50, sameVolume: false)

        let item = try #require(await store.add([source]).first)

        #expect(item.isReference)
        #expect(store.url(for: item)?.standardizedFileURL.path == source.standardizedFileURL.path)
        #expect(box.itemFolders().isEmpty)
    }

    @Test func copiesASmallFileFromAnotherVolume() async throws {
        let box = try Sandbox()
        let source = try box.file("note.txt", bytes: 10)
        let store = box.store(threshold: 50, sameVolume: false)

        let item = try #require(await store.add([source]).first)

        #expect(!item.isReference)
    }

    @Test func copiesALargeFileFromTheSameVolume() async throws {
        let box = try Sandbox()
        let source = try box.file("movie.mov", bytes: 100)
        let store = box.store(threshold: 50, sameVolume: true)

        let item = try #require(await store.add([source]).first)

        #expect(!item.isReference)
    }

    @Test func ignoresFilesDraggedBackFromTheShelf() async throws {
        let box = try Sandbox()
        let store = box.store()
        let item = try #require(await store.add([try box.file("a.txt")]).first)

        let again = await store.add([try #require(store.url(for: item))])

        #expect(again.isEmpty)
        #expect(store.items.count == 1)
    }

    @Test func reportsFilesThatCannotBeAdded() async throws {
        let box = try Sandbox()
        let store = box.store()

        let added = await store.add([box.sources.appending(path: "missing.txt")])

        #expect(added.isEmpty)
        #expect(store.items.isEmpty)
        #expect(store.failureMessage == "Couldn’t add “missing.txt”")
        #expect(box.itemFolders().isEmpty)
    }

    @Test func removesExpiredItemsAndTheirFiles() async throws {
        let box = try Sandbox()
        let store = box.store(retention: 3600)
        let old = try #require(await store.add([try box.file("old.txt")]).first)
        box.clock.addTimeInterval(1800)
        let fresh = try #require(await store.add([try box.file("fresh.txt")]).first)

        box.clock.addTimeInterval(1801)
        await store.purgeExpired()

        #expect(store.items == [fresh])
        #expect(box.itemFolders() == [fresh.id.uuidString])
        #expect(!box.itemFolders().contains(old.id.uuidString))
    }

    @Test func keepsItemsUntilTheirTimeIsUp() async throws {
        let box = try Sandbox()
        let store = box.store(retention: 3600)
        _ = await store.add([try box.file("a.txt")])

        box.clock.addTimeInterval(3599)
        await store.purgeExpired()

        #expect(store.items.count == 1)
    }

    @Test func removesOneItem() async throws {
        let box = try Sandbox()
        let store = box.store()
        let added = await store.add([try box.file("a.txt"), try box.file("b.txt")])

        store.remove(added[0].id)
        await store.flush()

        #expect(store.items == [added[1]])
        #expect(box.itemFolders() == [added[1].id.uuidString])
    }

    @Test func clearsTheShelf() async throws {
        let box = try Sandbox()
        let store = box.store()
        _ = await store.add([try box.file("a.txt"), try box.file("b.txt")])

        store.removeAll()
        await store.flush()

        #expect(store.items.isEmpty)
        #expect(box.itemFolders().isEmpty)
    }

    @Test func survivesARestart() async throws {
        let box = try Sandbox()
        let first = box.store()
        let added = await first.add([try box.file("a.txt"), try box.file("big.mov", bytes: 100)])
        await first.flush()

        let second = box.store()
        await second.load()

        #expect(second.items == added)
        let copy = try #require(second.url(for: added[0]))
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func dropsLeftoversOnLoad() async throws {
        let box = try Sandbox()
        let first = box.store()
        let kept = try #require(await first.add([try box.file("kept.txt")]).first)
        let lost = try #require(await first.add([try box.file("lost.txt")]).first)
        await first.flush()
        // A folder without an index entry, as after a crash mid-copy…
        let orphan = box.root.appending(path: "items/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        // …and an entry whose copy has disappeared.
        try FileManager.default.removeItem(at: try #require(first.url(for: lost)).deletingLastPathComponent())

        let second = box.store()
        await second.load()

        #expect(second.items == [kept])
        #expect(box.itemFolders() == [kept.id.uuidString])
    }

    @Test func expiresItemsThatOutlivedARestart() async throws {
        let box = try Sandbox()
        let first = box.store(retention: 3600)
        _ = await first.add([try box.file("a.txt")])
        await first.flush()

        box.clock.addTimeInterval(7200)
        let second = box.store(retention: 3600)
        await second.load()

        #expect(second.items.isEmpty)
        #expect(box.itemFolders().isEmpty)
    }

    @Test func marksALinkWhoseOriginalIsGone() async throws {
        let box = try Sandbox()
        let source = try box.file("movie.mov", bytes: 100)
        let store = box.store(threshold: 50, sameVolume: false)
        let item = try #require(await store.add([source]).first)

        store.refreshAvailability()
        #expect(store.missingItemIDs.isEmpty)

        try FileManager.default.removeItem(at: source)
        store.refreshAvailability()
        #expect(store.missingItemIDs == [item.id])
    }

    @Test func totalsTheSizeOfItems() async throws {
        let box = try Sandbox()
        let store = box.store()
        _ = await store.add([try box.file("a.txt", bytes: 100), try box.file("b.txt", bytes: 50)])

        #expect(store.totalSize == 150)
    }
}
