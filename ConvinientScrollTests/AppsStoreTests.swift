import Foundation
import Testing
@testable import MacToolkit

@Suite("AppsStore")
struct AppsStoreTests {
    /// A unique temporary root, removed when the test's sandbox goes out of scope.
    final class Sandbox {
        let root: URL

        init() {
            root = FileManager.default.temporaryDirectory
                .appending(path: "AppsStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        }

        deinit { try? FileManager.default.removeItem(at: root) }
    }

    static func app(_ bundleID: String, name: String) -> InstalledApp {
        InstalledApp(
            path: "/Applications/\(name).app",
            bundleID: bundleID,
            name: name,
            executable: name,
            version: "1.0",
            teamID: "ABCDE12345",
            nestedBundleIDs: [],
            infoPlistModified: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @Test func indexRoundTrip() {
        let sandbox = Sandbox()
        let store = AppsStore(root: sandbox.root)
        let apps = [Self.app("com.example.alpha", name: "Alpha"), Self.app("com.example.beta", name: "Beta")]

        store.saveIndex(apps)

        #expect(store.loadIndex() == apps)
    }

    @Test func missingIndexIsNil() {
        let sandbox = Sandbox()

        #expect(AppsStore(root: sandbox.root).loadIndex() == nil)
    }

    @Test func corruptIndexIsNil() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try "{".write(to: sandbox.root.appending(path: "index.json"), atomically: true, encoding: .utf8)

        #expect(AppsStore(root: sandbox.root).loadIndex() == nil)
    }

    @Test func removedRoundTrip() {
        let sandbox = Sandbox()
        let store = AppsStore(root: sandbox.root)
        let removed = [
            RemovedApp(app: Self.app("com.example.gamma", name: "Gamma"),
                       removedAt: Date(timeIntervalSince1970: 1_800_000_500))
        ]

        #expect(store.loadRemoved().isEmpty)

        store.saveRemoved(removed)

        #expect(store.loadRemoved() == removed)
    }
}
