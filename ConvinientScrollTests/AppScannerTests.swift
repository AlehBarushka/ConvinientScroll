import Foundation
import Testing
@testable import MacToolkit

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@Suite("AppScanner") struct AppScannerTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "AppScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func makeBundle(_ relativePath: String, plist: [String: Any]) throws -> URL {
        let bundle = root.appending(path: relativePath, directoryHint: .isDirectory)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    func scan(maxDepth: Int = 3, roots: [URL]? = nil, reusing: [InstalledApp] = [], teamID: @escaping @Sendable (URL) -> String? = { _ in nil }) -> [InstalledApp] {
        AppScanner(roots: roots ?? [root], maxDepth: maxDepth, teamID: teamID).scan(reusing: reusing)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @Test func findsAppsInSubfoldersUpToDepth() throws {
        defer { cleanUp() }
        try makeBundle("A.app", plist: ["CFBundleIdentifier": "com.example.a"])
        try makeBundle("Utilities/B.app", plist: ["CFBundleIdentifier": "com.example.b"])
        try makeBundle("a/b/c/D.app", plist: ["CFBundleIdentifier": "com.example.d"])
        let ids = scan().map(\.bundleID).sorted()
        #expect(ids == ["com.example.a", "com.example.b"])
    }

    @Test func ignoresAppsInsideApps() throws {
        defer { cleanUp() }
        try makeBundle("A.app", plist: ["CFBundleIdentifier": "com.example.a"])
        try makeBundle("A.app/Contents/Helpers/H.app", plist: ["CFBundleIdentifier": "com.example.a.h"])
        let ids = scan().map(\.bundleID)
        #expect(ids == ["com.example.a"])
    }

    @Test func readsIdentityAndNestedIDs() throws {
        defer { cleanUp() }
        let bundle = try makeBundle("A.app", plist: [
            "CFBundleIdentifier": "com.example.a",
            "CFBundleName": "A",
            "CFBundleExecutable": "AExec",
            "CFBundleShortVersionString": "2.1",
            "CFBundleVersion": "21",
        ])
        let plugin = bundle.appending(path: "Contents/PlugIns/W.appex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plugin.appending(path: "Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.a.widget"], format: .xml, options: 0)
            .write(to: plugin.appending(path: "Contents/Info.plist"))
        let launch = bundle.appending(path: "Contents/Library/LaunchServices", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: launch, withIntermediateDirectories: true)
        try Data().write(to: launch.appending(path: "com.example.a.helper"))

        let apps = scan(teamID: { _ in "ABCDE12345" })
        #expect(apps.count == 1)
        let app = try #require(apps.first)
        #expect(app.bundleID == "com.example.a")
        #expect(app.name == "A")
        #expect(app.executable == "AExec")
        #expect(app.version == "2.1")
        #expect(app.teamID == "ABCDE12345")
        #expect(app.nestedBundleIDs == ["com.example.a.helper", "com.example.a.widget"])
    }

    @Test func skipsBundlesWithoutIdentifier() throws {
        defer { cleanUp() }
        try makeBundle("A.app", plist: ["CFBundleName": "A"])
        try makeBundle("B.app", plist: ["CFBundleIdentifier": "com.example.b"])
        #expect(scan().map(\.bundleID) == ["com.example.b"])
    }

    @Test func emptyIdentifiersAreDropped() throws {
        defer { cleanUp() }
        try makeBundle("Empty.app", plist: ["CFBundleIdentifier": ""])
        try makeBundle("A.app", plist: ["CFBundleIdentifier": "com.example.a"])
        try makeBundle("A.app/Contents/PlugIns/W.appex", plist: ["CFBundleIdentifier": ""])
        try makeBundle("A.app/Contents/PlugIns/V.appex", plist: ["CFBundleIdentifier": "com.example.a.v"])

        let apps = scan(teamID: { _ in "" })

        #expect(apps.map(\.bundleID) == ["com.example.a"])
        #expect(apps.first?.nestedBundleIDs == ["com.example.a.v"])
        #expect(apps.first?.teamID == nil)
    }

    @Test func reusesUnchangedEntries() throws {
        defer { cleanUp() }
        try makeBundle("A.app", plist: ["CFBundleIdentifier": "com.example.a"])
        let counter = CallCounter()
        let teamID: @Sendable (URL) -> String? = { _ in counter.increment(); return "ABCDE12345" }
        let first = scan(teamID: teamID)
        #expect(counter.count == 1)
        let second = scan(reusing: first, teamID: teamID)
        #expect(counter.count == 1)
        #expect(second == first)
    }

    @Test func missingRootIsIgnored() throws {
        defer { cleanUp() }
        try makeBundle("A.app", plist: ["CFBundleIdentifier": "com.example.a"])
        let missing = root.appending(path: "Missing", directoryHint: .isDirectory)
        #expect(scan(roots: [missing, root]).map(\.bundleID) == ["com.example.a"])
    }
}
