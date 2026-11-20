import Foundation
import Testing
@testable import MacToolkit

@MainActor
@Suite("UpdateInstaller") struct UpdateInstallerTests {
    nonisolated final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []

        func append(_ value: Double) {
            lock.withLock { stored.append(value) }
        }

        var values: [Double] { lock.withLock { stored } }
    }

    struct HelperFailure: Error {}

    @MainActor
    final class Harness {
        let root: URL
        let suiteName = "UpdateInstallerTests-\(UUID().uuidString)"
        let store: PendingUpdateStore
        var journal: [String] = []
        var helperArguments: [String]?
        var staging: URL?
        var dmgExistedAtLaunch = true
        var environment: UpdateInstallerEnvironment!

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "UpdateInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = PendingUpdateStore(defaults: UserDefaults(suiteName: suiteName)!)
            let target = root.appending(path: "Applications/MacToolkit.app")

            environment = UpdateInstallerEnvironment(
                download: { [unowned self] _, destination, progress in
                    journal.append("download")
                    try Data("dmg".utf8).write(to: destination)
                    progress(0.5)
                    progress(1)
                },
                extractApp: { [unowned self] dmg, directory in
                    journal.append("extract")
                    #expect(dmg == directory.appending(path: "update.dmg"))
                    let app = directory.appending(path: "MacToolkit.app", directoryHint: .isDirectory)
                    try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
                    return app
                },
                identity: { [unowned self] _ in
                    journal.append("identity")
                    return SigningIdentity(teamID: "TEAM1", bundleID: "com.example.toolkit")
                },
                currentIdentity: { SigningIdentity(teamID: "TEAM1", bundleID: "com.example.toolkit") },
                versionOfApp: { _ in "2.4.0" },
                isWritable: { _ in true },
                fileExists: { _ in false },
                makeStagingDirectory: { [unowned self] in
                    let directory = root.appending(path: "Staging", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    staging = directory
                    return directory
                },
                launchHelper: { [unowned self] arguments in
                    journal.append("launchHelper")
                    helperArguments = arguments
                    dmgExistedAtLaunch = FileManager.default.fileExists(
                        atPath: root.appending(path: "Staging/update.dmg").path)
                },
                terminate: { [unowned self] in journal.append("terminate") },
                loginItemEnabled: { false },
                unregisterLoginItem: { [unowned self] in journal.append("unregister") },
                pending: store,
                targetURL: target,
                currentAppURL: target
            )
        }

        var stagingExists: Bool {
            FileManager.default.fileExists(atPath: root.appending(path: "Staging").path)
        }

        func install(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws(UpdateError) {
            try await UpdateInstaller(environment: environment).install(Harness.update, progress: progress)
        }

        func installError() async -> UpdateError? {
            do {
                try await install()
                return nil
            } catch {
                return error
            }
        }

        func cleanUp() {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        static let update = AvailableUpdate(
            version: AppVersion("2.4.0")!,
            pageURL: URL(string: "https://example.com/releases/v2.4.0")!,
            diskImageURL: URL(string: "https://example.com/MacToolkit-2.4.0.dmg")!
        )
    }

    @Test func happyPathLaunchesHelperThenTerminates() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        let progress = ProgressLog()

        try await h.install(progress: { progress.append($0) })

        #expect(h.journal == ["download", "extract", "identity", "launchHelper", "terminate"])
        let staging = try #require(h.staging)
        let arguments = try #require(h.helperArguments)
        let script = staging.appending(path: "install-update.sh")
        #expect(arguments.count == 7)
        #expect(arguments.first == "/bin/sh")
        #expect(arguments.dropFirst().first == script.path)
        #expect(Array(arguments.dropFirst(2)) == [
            "\(getpid())",
            staging.appending(path: "MacToolkit.app").path,
            h.environment.targetURL.path,
            h.environment.currentAppURL.path,
            PendingUpdateStore.failureFileURL.path,
        ])
        let bundled = try #require(Bundle.main.url(forResource: "install-update", withExtension: "sh"))
        #expect(try Data(contentsOf: script) == Data(contentsOf: bundled))
        #expect(!h.dmgExistedAtLaunch)
        #expect(h.store.load() == PendingUpdate(version: "2.4.0", reregisterLoginItem: false))
        #expect(progress.values == [0.5, 1])
    }

    @Test func notWritableFailsBeforeDownload() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.isWritable = { $0 != "/Applications" }

        #expect(await h.installError() == .applicationsNotWritable)
        #expect(h.journal.isEmpty)
        #expect(h.staging == nil)
    }

    @Test func existingTargetMustBeWritable() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        let target = h.environment.targetURL.path
        h.environment.fileExists = { $0 == target }
        h.environment.isWritable = { $0 != target }

        #expect(await h.installError() == .applicationsNotWritable)
        #expect(h.journal.isEmpty)
        #expect(h.staging == nil)
    }

    @Test func wrongTeamDoesNotTerminate() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.identity = { _ in SigningIdentity(teamID: "TEAM2", bundleID: "com.example.toolkit") }

        #expect(await h.installError() == .wrongDeveloper)
        #expect(!h.journal.contains("launchHelper"))
        #expect(!h.journal.contains("terminate"))
        #expect(h.staging != nil)
        #expect(!h.stagingExists)
        #expect(h.store.load() == nil)
    }

    @Test func versionMismatchIsRejected() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.versionOfApp = { _ in "2.3.9" }

        #expect(await h.installError() == .versionMismatch(found: "2.3.9", expected: "2.4.0"))
        #expect(!h.journal.contains("terminate"))
        #expect(!h.stagingExists)
    }

    @Test func extractErrorIsPassedThrough() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.extractApp = { _, _ throws(UpdateError) in throw .appNotInImage }

        #expect(await h.installError() == .appNotInImage)
        #expect(!h.stagingExists)
    }

    @Test func cancelledPrepareRemovesStaging() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.download = { _, _, _ in throw CancellationError() }

        #expect(await h.installError() == .cancelled)
        #expect(h.staging != nil)
        #expect(!h.stagingExists)
        #expect(h.store.load() == nil)
    }

    @Test func cancelledURLSessionDownloadIsCancelled() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.download = { _, _, _ in throw URLError(.cancelled) }

        #expect(await h.installError() == .cancelled)
        #expect(!h.stagingExists)
    }

    @Test func otherDownloadErrorsAreNetworkErrors() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.download = { _, _, _ in throw URLError(.notConnectedToInternet) }

        #expect(await h.installError() == .network)
        #expect(!h.journal.contains("extract"))
        #expect(!h.stagingExists)
    }

    @Test func cancellingTheTaskStopsTheDownload() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        let started = AsyncStream<Void>.makeStream()
        h.environment.download = { _, _, _ in
            started.continuation.yield()
            try await Task.sleep(for: .seconds(30))
        }

        let task = Task { await h.installError() }
        for await _ in started.stream { break }
        task.cancel()

        #expect(await task.value == .cancelled)
        #expect(!h.stagingExists)
        #expect(!h.journal.contains("extract"))
    }

    @Test func cancellationAfterVerifyStopsBeforeHandOff() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        let extract = h.environment.extractApp
        h.environment.extractApp = { dmg, directory throws(UpdateError) in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await extract(dmg, directory)
        }

        let task = Task { await h.installError() }
        #expect(await task.value == .cancelled)
        #expect(h.journal.contains("identity"))
        #expect(!h.journal.contains("launchHelper"))
        #expect(!h.journal.contains("terminate"))
        #expect(!h.stagingExists)
        #expect(h.store.load() == nil)
    }

    @Test func helperLaunchFailureCleansUp() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.loginItemEnabled = { true }
        h.environment.currentAppURL = h.root.appending(path: "Home/Applications/MacToolkit.app")
        h.environment.launchHelper = { _ in throw HelperFailure() }

        #expect(await h.installError() != nil)
        #expect(!h.journal.contains("terminate"))
        #expect(!h.journal.contains("unregister"))
        #expect(!h.stagingExists)
        #expect(h.store.load() == nil)
    }

    @Test func loginItemOutsideApplicationsIsUnregistered() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.loginItemEnabled = { true }
        h.environment.currentAppURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Applications/MacToolkit.app", directoryHint: .isDirectory)

        try await h.install()

        #expect(h.journal.contains("unregister"))
        #expect(h.journal.last == "terminate")
        #expect(h.store.load() == PendingUpdate(version: "2.4.0", reregisterLoginItem: true))
    }

    @Test func loginItemInApplicationsIsKept() async throws {
        let h = try Harness()
        defer { h.cleanUp() }
        h.environment.loginItemEnabled = { true }
        h.environment.currentAppURL = URL(filePath: h.environment.targetURL.path + "/", directoryHint: .isDirectory)

        try await h.install()

        #expect(!h.journal.contains("unregister"))
        #expect(h.journal.last == "terminate")
        #expect(h.store.load() == PendingUpdate(version: "2.4.0", reregisterLoginItem: true))
    }
}

@Suite("PendingUpdateStore") struct PendingUpdateStoreTests {
    @Test func savesLoadsAndClears() throws {
        let suiteName = "PendingUpdateStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PendingUpdateStore(defaults: defaults)
        let pending = PendingUpdate(version: "2.4.0", reregisterLoginItem: true)

        #expect(store.load() == nil)
        store.save(pending)
        #expect(PendingUpdateStore(defaults: defaults).load() == pending)
        #expect(defaults.data(forKey: "PendingUpdate") != nil)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func failureFileLivesInApplicationSupport() {
        let url = PendingUpdateStore.failureFileURL
        #expect(url.lastPathComponent == "failure.txt")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Update")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            == Bundle.main.bundleIdentifier)
        #expect(url.path.hasPrefix(URL.applicationSupportDirectory.path))
    }
}

@Suite("UpdateDownload") struct UpdateDownloadTests {
    @Test func downloadsFileURL() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.dmg")
        try Data("image".utf8).write(to: source)
        let destination = root.appending(path: "update.dmg")
        try await UpdateInstallerEnvironment.download(source, to: destination) { _ in }
        #expect(try Data(contentsOf: destination) == Data("image".utf8))
    }
}
