import Foundation
import Testing
@testable import MacToolkit

@Suite("InstallScript") struct InstallScriptTests {
    struct Sandbox {
        let root: URL
        var applications: URL { root.appendingPathComponent("Applications") }
        var staging: URL { root.appendingPathComponent("Staging") }
        var target: URL { applications.appendingPathComponent("Mac Toolkit.app") }
        var staged: URL { staging.appendingPathComponent("Mac Toolkit.app") }
        var fallback: URL { root.appendingPathComponent("Fallback/Mac Toolkit.app") }
        var backup: URL { applications.appendingPathComponent(".Mac Toolkit.app.update-backup") }
        var failure: URL { root.appendingPathComponent("Support/Update/failure.txt") }
        var opened: URL { root.appendingPathComponent("opened.txt") }
        var fakeOpen: URL { root.appendingPathComponent("fake-open.sh") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("install-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try writeExecutable(fakeOpen, "#!/bin/sh\necho \"$1\" >> \"\(opened.path)\"\n")
        }

        func writeExecutable(_ url: URL, _ text: String) throws {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        func makeBundle(_ url: URL, version: String) throws {
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try "plist".write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            try version.write(to: contents.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        }

        func makeFlakyMove(failingCalls: [Int]) throws -> URL {
            let counter = root.appendingPathComponent("move-count")
            let shim = root.appendingPathComponent("flaky-move.sh")
            let pattern = failingCalls.map(String.init).joined(separator: "|")
            try writeExecutable(shim, """
            #!/bin/sh
            echo x >> "\(counter.path)"
            case "$(wc -l < "\(counter.path)" | tr -d ' ')" in
                \(pattern)) exit 1 ;;
            esac
            exec /bin/mv "$@"
            """)
            return shim
        }

        func version(of url: URL) -> String? {
            try? String(contentsOf: url.appendingPathComponent("Contents/version.txt"), encoding: .utf8)
        }

        func openedPaths() -> [String] {
            guard let text = try? String(contentsOf: opened, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").map(String.init)
        }

        func failureText() -> String? { try? String(contentsOf: failure, encoding: .utf8) }

        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        func run(pid: Int32, environment: [String: String] = [:]) throws -> Int32 {
            let script = try #require(Bundle.main.url(forResource: "install-update", withExtension: "sh"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(pid), staged.path, target.path, fallback.path, failure.path]
            var env = ProcessInfo.processInfo.environment
            env["MT_UPDATE_OPEN"] = fakeOpen.path
            for (key, value) in environment { env[key] = value }
            process.environment = env
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }

        func runAfterShortSleep(environment: [String: String] = [:]) throws -> Int32 {
            let sleeper = Process()
            sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
            sleeper.arguments = ["0.3"]
            try sleeper.run()
            return try run(pid: sleeper.processIdentifier, environment: environment)
        }
    }

    @Test func replacesExistingAppAndLaunchesIt() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.target, version: "old")
        try box.makeBundle(box.staged, version: "new")
        let status = try box.runAfterShortSleep()
        #expect(status == 0)
        #expect(box.version(of: box.target) == "new")
        #expect(!box.exists(box.backup))
        #expect(!box.exists(box.staged))
        #expect(box.openedPaths() == [box.target.path])
        #expect(!box.exists(box.failure))
    }

    @Test func installsWhenTargetMissing() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.staged, version: "new")
        let status = try box.runAfterShortSleep()
        #expect(status == 0)
        #expect(box.version(of: box.target) == "new")
        #expect(box.openedPaths() == [box.target.path])
    }

    @Test func restoresBackupWhenMoveFails() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.target, version: "old")
        try box.makeBundle(box.staged, version: "new")
        let flaky = try box.makeFlakyMove(failingCalls: [2])
        let status = try box.runAfterShortSleep(environment: ["MT_UPDATE_MOVE": flaky.path])
        #expect(status == 1)
        #expect(box.version(of: box.target) == "old")
        #expect(!box.exists(box.backup))
        #expect(box.openedPaths() == [box.target.path])
        #expect(box.failureText() == "The new version couldn't be moved to Applications.\n")
    }

    @Test func rollbackFailureLaunchesFallback() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.target, version: "old")
        try box.makeBundle(box.staged, version: "new")
        try box.makeBundle(box.fallback, version: "old")
        let flaky = try box.makeFlakyMove(failingCalls: [2, 3])
        let status = try box.runAfterShortSleep(environment: ["MT_UPDATE_MOVE": flaky.path])
        #expect(status == 1)
        #expect(!box.exists(box.target))
        #expect(box.version(of: box.backup) == "old")
        #expect(box.openedPaths() == [box.fallback.path])
        #expect(box.failureText() == "The new version couldn't be moved to Applications, and the previous version couldn't be put back. It is kept in the Applications folder as .Mac Toolkit.app.update-backup.\n")
    }

    @Test func rollbackFailureLaunchesBackupWithoutFallback() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.target, version: "old")
        try box.makeBundle(box.staged, version: "new")
        let flaky = try box.makeFlakyMove(failingCalls: [2, 3])
        let status = try box.runAfterShortSleep(environment: ["MT_UPDATE_MOVE": flaky.path])
        #expect(status == 1)
        #expect(!box.exists(box.target))
        #expect(box.openedPaths() == [box.backup.path])
    }

    @Test func leftoverBackupThatCannotBeRemovedAbortsBeforeMoving() throws {
        let box = try Sandbox()
        let locked = box.backup.appendingPathComponent("Locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            box.cleanUp()
        }
        try box.makeBundle(box.target, version: "old")
        try box.makeBundle(box.staged, version: "new")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        try box.makeBundle(box.fallback, version: "old")
        let status = try box.runAfterShortSleep()
        #expect(status == 1)
        #expect(box.version(of: box.target) == "old")
        #expect(box.version(of: box.staged) == "new")
        #expect(box.openedPaths() == [box.fallback.path])
        #expect(box.failureText() == "The old version couldn't be moved aside.\n")
    }

    @Test func launchesFallbackWhenNothingToRestore() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.staged, version: "new")
        try box.makeBundle(box.fallback, version: "old")
        let status = try box.runAfterShortSleep(environment: ["MT_UPDATE_MOVE": "/usr/bin/false"])
        #expect(status == 1)
        #expect(!box.exists(box.target))
        #expect(box.openedPaths() == [box.fallback.path])
        #expect(box.failureText() == "The new version couldn't be moved to Applications.\n")
    }

    @Test func timeoutLeavesTargetUntouched() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.target, version: "old")
        try box.makeBundle(box.staged, version: "new")
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["5"]
        try sleeper.run()
        defer {
            sleeper.terminate()
            sleeper.waitUntilExit()
        }
        let status = try box.run(pid: sleeper.processIdentifier, environment: ["MT_UPDATE_TIMEOUT": "1"])
        #expect(status == 1)
        #expect(box.version(of: box.target) == "old")
        #expect(box.version(of: box.staged) == "new")
        #expect(box.openedPaths().isEmpty)
        #expect(box.failureText() == "The app didn't quit in time.\n")
    }

    @Test func removesStaleBackup() throws {
        let box = try Sandbox()
        defer { box.cleanUp() }
        try box.makeBundle(box.backup, version: "stale")
        try box.makeBundle(box.staged, version: "new")
        let status = try box.runAfterShortSleep()
        #expect(status == 0)
        #expect(!box.exists(box.backup))
        #expect(box.version(of: box.target) == "new")
    }

    @Test func scriptIsInAppResources() {
        #expect(Bundle.main.url(forResource: "install-update", withExtension: "sh") != nil)
    }
}
