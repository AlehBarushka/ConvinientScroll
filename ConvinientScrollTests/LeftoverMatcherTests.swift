import Foundation
import Testing
@testable import MacToolkit

@Suite("LeftoverMatcher") struct LeftoverMatcherTests {
    static let chatter = InstalledApp(path: "/Applications/Chatter.app", bundleID: "com.example.chatter", name: "Chatter",
        executable: "Chatter Desktop", version: "5.8", teamID: "ABCDE12345", nestedBundleIDs: ["com.example.chatter.helper"], infoPlistModified: .distantPast)
    static let sibling = InstalledApp(path: "/Applications/Chatter Notes.app", bundleID: "com.example.chatternotes", name: "Chatter Notes",
        executable: nil, version: nil, teamID: "ABCDE12345", nestedBundleIDs: [], infoPlistModified: .distantPast)
    func entry(_ folder: LibraryFolder, _ name: String, _ domain: LibraryDomain = .user) -> LibraryEntry {
        LibraryEntry(url: URL(filePath: "/L/\(folder.rawValue)/\(name)"), domain: domain, folder: folder)
    }

    @Test func bundleIDMatches() {
        for (folder, name) in [(LibraryFolder.preferences, "com.example.chatter.plist"), (.caches, "com.example.chatter"),
                               (.caches, "com.example.chatter.ShipIt"), (.savedState, "com.example.chatter.savedState"),
                               (.cookies, "com.example.chatter.binarycookies"), (.groupContainers, "group.com.example.chatter"),
                               (.launchAgents, "com.example.chatter.helper.plist")] {
            #expect(LeftoverMatcher.match(entry(folder, name), app: Self.chatter, installed: []) == .bundleID)
        }
        #expect(LeftoverMatcher.match(entry(.preferences, "com.example.chatterbox.plist"), app: Self.chatter, installed: []) == nil)
    }
    @Test func teamIDMatchesOnlyWhenNoOtherAppSharesIt() {
        let group = entry(.groupContainers, "ABCDE12345.com.example.shared")
        #expect(LeftoverMatcher.match(group, app: Self.chatter, installed: []) == .teamID)
        #expect(LeftoverMatcher.match(group, app: Self.chatter, installed: [Self.sibling]) == nil)
    }
    @Test func nameMatchesOnlyInNamedFolders() {
        #expect(LeftoverMatcher.match(entry(.applicationSupport, "Chatter Desktop"), app: Self.chatter, installed: []) == .name)
        #expect(LeftoverMatcher.match(entry(.logs, "chatter"), app: Self.chatter, installed: []) == .name)
        #expect(LeftoverMatcher.match(entry(.preferences, "Chatter"), app: Self.chatter, installed: []) == nil)
    }
    @Test func nameMatchSkippedWhenAnotherAppHasTheName() {
        let other = InstalledApp(path: "/Applications/Utilities/Chatter.app", bundleID: "com.example.other", name: "Chatter",
            executable: nil, version: nil, teamID: nil, nestedBundleIDs: [], infoPlistModified: .distantPast)
        #expect(LeftoverMatcher.match(entry(.applicationSupport, "Chatter"), app: Self.chatter, installed: [other]) == nil)
    }
    @Test func appleIsNeverOffered() {
        #expect(LeftoverMatcher.isApple("com.apple.Safari.plist"))
        #expect(LeftoverMatcher.isApple("group.com.apple.notes"))
        #expect(!LeftoverMatcher.isApple("com.applesauce.app"))
    }
    @Test func entryIDs() {
        #expect(LeftoverMatcher.entryID("com.example.oldplayer.plist", folder: .preferences) == "com.example.oldplayer")
        #expect(LeftoverMatcher.entryID("ABCDE12345.com.example.shared", folder: .groupContainers) == "com.example.shared")
        #expect(LeftoverMatcher.entryID("com.example.tool.0123456789AB.plist", folder: .preferencesByHost) == "com.example.tool")
        #expect(LeftoverMatcher.entryID("OldPlayer", folder: .applicationSupport) == nil)
        #expect(LeftoverMatcher.entryID("example.plist", folder: .preferences) == nil)
    }
    @Test func defaultSelection() {
        let user = entry(.containers, "com.example.chatter")
        #expect(LeftoverItem.make(user, match: .bundleID, canReadProtected: false).isSelectedByDefault == false)
        #expect(LeftoverItem.make(user, match: .bundleID, canReadProtected: true).isSelectedByDefault == true)
        #expect(LeftoverItem.make(entry(.applicationSupport, "Chatter"), match: .name, canReadProtected: true).isSelectedByDefault == false)
        #expect(LeftoverItem.make(entry(.launchDaemons, "com.example.chatter.helper.plist", .system), match: .bundleID, canReadProtected: false).needsAdmin)
    }
    @Test func entryOwnedByAnotherInstalledAppIsNeverOffered() {
        let foo = InstalledApp(path: "/Applications/Foo.app", bundleID: "com.example.foo", name: "Foo",
            executable: nil, version: nil, teamID: nil, nestedBundleIDs: [], infoPlistModified: .distantPast)
        let pro = InstalledApp(path: "/Applications/Foo Pro.app", bundleID: "com.example.foo.pro", name: "Foo Pro",
            executable: nil, version: nil, teamID: nil, nestedBundleIDs: [], infoPlistModified: .distantPast)
        let prefs = entry(.preferences, "com.example.foo.pro.plist")
        #expect(LeftoverMatcher.match(prefs, app: foo, installed: [pro]) == nil)
        #expect(LeftoverMatcher.match(prefs, app: foo, installed: []) == .bundleID)
    }
    @Test func indexedLookupKeepsTheMatchingRules() {
        let pro = InstalledApp(path: "/Applications/Chatter Pro.app", bundleID: "com.example.chatter.pro", name: "Chatter Pro",
            executable: nil, version: nil, teamID: "FGHIJ67890", nestedBundleIDs: [], infoPlistModified: .distantPast)
        let installed = [Self.chatter, pro]
        let owners = OwnerIndex(installed)
        let cases: [(LibraryEntry, MatchKind?)] = [
            (entry(.preferences, "com.example.chatter.plist"), .bundleID),
            (entry(.caches, "COM.EXAMPLE.CHATTER.ShipIt"), .bundleID),
            (entry(.launchAgents, "com.example.chatter.helper.plist"), .bundleID),
            (entry(.groupContainers, "group.com.example.chatter"), .bundleID),
            (entry(.groupContainers, "group.com.example.chatter.shared"), .bundleID),
            (entry(.groupContainers, "ABCDE12345.com.example.shared"), .teamID),
            (entry(.groupContainers, "FGHIJ67890.com.example.shared"), nil),
            (entry(.preferences, "com.apple.chatter.plist"), nil),
            (entry(.groupContainers, "group.com.apple.chatter"), nil),
            (entry(.caches, "com.example.chatter.pro"), nil),
            (entry(.caches, "com.example.chatter.pro.cache"), nil),
            (entry(.groupContainers, "group.com.example.chatter.pro"), nil),
            (entry(.applicationSupport, "Chatter Desktop"), .name),
            (entry(.applicationSupport, "Chatter Pro"), nil),
            (entry(.caches, "com.example.chatterbox"), nil),
        ]
        for (entry, expected) in cases {
            #expect(LeftoverMatcher.match(entry, app: Self.chatter, owners: owners) == expected, "\(entry.name)")
            #expect(LeftoverMatcher.match(entry, app: Self.chatter, installed: installed) == expected, "\(entry.name)")
        }
    }
    @Test func appleAppsAreNotMatchedByName() {
        let music = InstalledApp(path: "/Applications/Musical.app", bundleID: "com.apple.musical", name: "Musical",
            executable: nil, version: nil, teamID: nil, nestedBundleIDs: [], infoPlistModified: .distantPast)
        #expect(LeftoverMatcher.match(entry(.applicationSupport, "Musical"), app: music, installed: [music]) == nil)
        #expect(LeftoverMatcher.match(entry(.caches, "Musical"), app: music, installed: [music]) == nil)
    }
    @Test func groupContainerOfASharedTeamIsNotOffered() {
        let group = entry(.groupContainers, "group.com.example.chatter")
        #expect(LeftoverMatcher.match(group, app: Self.chatter, installed: [Self.chatter]) == .bundleID)
        #expect(LeftoverMatcher.match(group, app: Self.chatter, installed: [Self.chatter, Self.sibling]) == nil)
        #expect(LeftoverMatcher.match(entry(.preferences, "group.com.example.chatter.plist"), app: Self.chatter,
                                      installed: [Self.chatter, Self.sibling]) == .bundleID)
        #expect(LeftoverMatcher.match(entry(.groupContainers, "com.example.chatter"), app: Self.chatter,
                                      installed: [Self.chatter, Self.sibling]) == .bundleID)
    }
    @Test func ownershipCoversBundleAndTeamRules() {
        let foo = InstalledApp(path: "/Applications/Foo.app", bundleID: "com.example.foo", name: "Foo", executable: nil,
            version: nil, teamID: "ABCDE12345", nestedBundleIDs: ["com.example.foo.agent"], infoPlistModified: .distantPast)
        let owners = OwnerIndex([foo])
        #expect(owners.owns(entry(.preferences, "com.example.foo.plist")))
        #expect(owners.owns(entry(.launchAgents, "com.example.foo.agent.plist")))
        #expect(owners.owns(entry(.groupContainers, "group.com.example.foo.data")))
        #expect(owners.owns(entry(.groupContainers, "ABCDE12345.com.example.other")))
        #expect(owners.owns(entry(.groupContainers, "FGHIJ67890.com.example.foo")))
        #expect(owners.owns(entry(.containers, "ABCDE12345.com.example.other")) == false)
        #expect(owners.owns(entry(.preferences, "com.example.food.plist")) == false)
        #expect(OwnerIndex([], alsoOwned: ["com.example.foo"]).owns(entry(.caches, "com.example.foo.ShipIt")))
    }
    @Test func entryIDStripping() {
        #expect(LeftoverMatcher.entryID("group.com.example.shared", folder: .groupContainers) == "com.example.shared")
        #expect(LeftoverMatcher.entryID("com.example.tool.0123ABCD-4567-89AB-CDEF-0123456789AB.plist", folder: .preferencesByHost) == "com.example.tool")
        #expect(LeftoverMatcher.entryID("com.example.tool.savedState", folder: .savedState) == "com.example.tool")
        #expect(LeftoverMatcher.entryID("com.example.tool.binarycookies", folder: .cookies) == "com.example.tool")
        #expect(LeftoverMatcher.entryID("com.example.tool.PLIST", folder: .preferences) == "com.example.tool")
        #expect(LeftoverMatcher.entryID("com.example.SAVEDSTATE", folder: .savedState) == nil)
        #expect(LeftoverMatcher.entryID("example.tool.plist", folder: .preferences) == nil)
        #expect(LeftoverMatcher.entryID("group.example", folder: .groupContainers) == nil)
    }
}
