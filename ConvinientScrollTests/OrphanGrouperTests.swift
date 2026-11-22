import Foundation
import Testing
@testable import MacToolkit

@Suite("OrphanGrouper") struct OrphanGrouperTests {
    static let editor = InstalledApp(path: "/Applications/Editor.app", bundleID: "com.example.editor", name: "Editor",
        executable: nil, version: nil, teamID: "ABCDE12345", nestedBundleIDs: ["com.example.editor.helper"], infoPlistModified: .distantPast)
    func entry(_ folder: LibraryFolder, _ name: String, _ domain: LibraryDomain = .user) -> LibraryEntry {
        LibraryEntry(url: URL(filePath: "/L/\(folder.rawValue)/\(name)"), domain: domain, folder: folder)
    }
    func groups(_ entries: [LibraryEntry], installed: [InstalledApp] = [], hidden: Set<String> = [], canReadProtected: Bool = true) -> [OrphanGroup] {
        OrphanGrouper.groups(entries, installed: installed, hidden: hidden, canReadProtected: canReadProtected)
    }

    @Test func ownedEntriesAreSkipped() {
        let result = groups([entry(.preferences, "com.example.editor.plist"), entry(.caches, "com.example.editor.ShipIt")],
                            installed: [Self.editor])
        #expect(result.isEmpty)
    }
    @Test func helpersOfInstalledAreOwned() {
        let app = InstalledApp(path: "/Applications/Editor.app", bundleID: "com.example.editor", name: "Editor",
            executable: nil, version: nil, teamID: nil, nestedBundleIDs: ["com.example.editor.helper"], infoPlistModified: .distantPast)
        #expect(groups([entry(.preferences, "com.example.editor.helper.plist")], installed: [app]).isEmpty)
    }
    @Test func groupsByShortestPrefix() {
        let result = groups([entry(.preferences, "com.example.oldplayer.plist"), entry(.caches, "com.example.oldplayer.helper"),
                             entry(.preferences, "com.example.oldplayerx.plist")])
        #expect(result.map(\.id) == ["com.example.oldplayer", "com.example.oldplayerx"])
        #expect(result[0].items.count == 2)
        #expect(result[1].items.count == 1)
        #expect(result[0].items.allSatisfy { $0.match == .bundleID && $0.size == nil })
    }
    @Test func appleAndHiddenAreSkipped() {
        let result = groups([entry(.preferences, "com.apple.Music.plist"), entry(.preferences, "com.example.cli-helper.plist")],
                            hidden: ["com.example.cli-helper"])
        #expect(result.isEmpty)
    }
    @Test func teamContainersOfInstalledAreSkipped() {
        #expect(groups([entry(.groupContainers, "ABCDE12345.com.example.x")], installed: [Self.editor]).isEmpty)
    }
    @Test func plainNamesAreSkipped() {
        #expect(groups([entry(.applicationSupport, "OldPlayer")]).isEmpty)
    }
    @Test func protectedWithoutAccessIsNotAccessible() {
        let result = groups([entry(.containers, "com.example.meetings")], canReadProtected: false)
        #expect(result.count == 1)
        #expect(result[0].items[0].isAccessible == false)
    }
}
