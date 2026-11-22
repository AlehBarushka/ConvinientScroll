import Foundation
import Testing
@testable import MacToolkit

@Suite("LibraryScanner") struct LibraryScannerTests {
    static let chatter = InstalledApp(path: "/Applications/Chatter.app", bundleID: "com.example.chatter", name: "Chatter",
        executable: nil, version: nil, teamID: nil, nestedBundleIDs: [], infoPlistModified: .distantPast)

    func withLibraries(canReadProtected: Bool = true, _ body: (LibraryScanner, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let user = root.appending(path: "User")
        let system = root.appending(path: "System")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(LibraryScanner(userLibrary: user, systemLibrary: system, canReadProtected: canReadProtected), user, system)
    }

    func make(_ url: URL, bytes: Int? = nil) throws {
        if let bytes {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    @Test func findsLeftoversInBothLibraries() throws {
        try withLibraries { scanner, user, system in
            try make(user.appending(path: "Preferences/com.example.chatter.plist"), bytes: 10)
            try make(user.appending(path: "Caches/com.example.chatter"))
            try make(system.appending(path: "LaunchDaemons/com.example.chatter.helper.plist"), bytes: 10)
            try make(user.appending(path: "Caches/com.example.other"))
            let items = scanner.leftovers(of: Self.chatter, installed: [Self.chatter])
            #expect(items.count == 3)
            #expect(items.map(\.entry.url.path) == items.map(\.entry.url.path).sorted())
            #expect(items.filter(\.needsAdmin).map(\.entry.name) == ["com.example.chatter.helper.plist"])
        }
    }

    @Test func sizesCountFolderContents() throws {
        try withLibraries { scanner, user, _ in
            let cache = user.appending(path: "Caches/com.example.chatter")
            try make(cache.appending(path: "a.bin"), bytes: 4096)
            try make(cache.appending(path: "b.bin"), bytes: 8192)
            let items = scanner.leftovers(of: Self.chatter, installed: [Self.chatter])
            #expect(items.count == 1)
            #expect((items[0].size ?? 0) >= 12288)
        }
    }

    @Test func protectedWithoutAccessHasNoSize() throws {
        try withLibraries(canReadProtected: false) { scanner, user, _ in
            try make(user.appending(path: "Containers/com.example.chatter/Data/file.bin"), bytes: 4096)
            let items = scanner.leftovers(of: Self.chatter, installed: [Self.chatter])
            #expect(items.count == 1)
            #expect(items[0].size == nil)
            #expect(items[0].isAccessible == false)
        }
    }

    @Test func missingFoldersAreFine() throws {
        try withLibraries { scanner, _, _ in
            #expect(scanner.leftovers(of: Self.chatter, installed: [Self.chatter]).isEmpty)
            #expect(scanner.entries().isEmpty)
        }
    }

    @Test func orphansUseTheGrouper() throws {
        try withLibraries { scanner, user, _ in
            try make(user.appending(path: "Preferences/com.example.oldplayer.plist"), bytes: 10)
            let groups = scanner.orphans(installed: [], hidden: [])
            #expect(groups.map(\.id) == ["com.example.oldplayer"])
        }
    }
}
