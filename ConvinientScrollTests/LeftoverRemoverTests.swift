import Foundation
import Testing
@testable import MacToolkit

@Suite("LeftoverRemover") struct LeftoverRemoverTests {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var calls: [String] { lock.withLock { storage } }
        func add(_ call: String) { lock.withLock { storage.append(call) } }
    }

    static let userTrash = URL(filePath: "/T")

    static func item(_ path: String, domain: LibraryDomain, folder: LibraryFolder, size: Int64? = nil) -> LeftoverItem {
        LeftoverItem(entry: LibraryEntry(url: URL(filePath: path), domain: domain, folder: folder),
                     match: .bundleID, size: size, isAccessible: true)
    }

    static func date(hour: Int, minute: Int, second: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 22
        parts.hour = hour; parts.minute = minute; parts.second = second
        return Calendar.current.date(from: parts)!
    }

    static func environment(
        recorder: Recorder,
        trashFails: Set<String> = [],
        privileged: @escaping @Sendable (String) throws(PrivilegedError) -> Void = { _ in },
        exists: @escaping @Sendable (URL) -> Bool = { _ in false }
    ) -> RemovalEnvironment {
        RemovalEnvironment(
            trash: { url in
                if trashFails.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
                recorder.add("trash \(url.path)")
            },
            bootoutUser: { recorder.add("bootout \($0.path)") },
            runPrivileged: { script throws(PrivilegedError) in
                recorder.add("privileged")
                try privileged(script)
            },
            exists: exists,
            userTrash: userTrash,
            now: { date(hour: 14, minute: 5, second: 9) }
        )
    }

    @Test func quotesAwkwardPaths() {
        let script = LeftoverRemover.privilegedScript(items: [URL(filePath: "/Library/Application Support/Bob's \"Tool\"")],
            services: [], destinations: [URL(filePath: "/T/Bob's \"Tool\"")])
        #expect(script == "/bin/mv -n '/Library/Application Support/Bob'\\''s \"Tool\"' '/T/Bob'\\''s \"Tool\"'")
        #expect(LeftoverRemover.appleScriptCommand("echo \"a\\b\"") == "do shell script \"echo \\\"a\\\\b\\\"\" with administrator privileges")
    }

    @Test func servicesStopBeforeFilesMove() {
        let plist = URL(filePath: "/Library/LaunchDaemons/x.plist")
        let helper = URL(filePath: "/Library/PrivilegedHelperTools/x")
        let script = LeftoverRemover.privilegedScript(items: [plist, helper], services: [plist],
                                                      destinations: [URL(filePath: "/T/x.plist"), URL(filePath: "/T/x")])
        let lines = script.split(separator: "\n").map(String.init)
        #expect(lines == [
            "/bin/launchctl bootout system '/Library/LaunchDaemons/x.plist' 2>/dev/null",
            "/bin/mv -n '/Library/LaunchDaemons/x.plist' '/T/x.plist'",
            "/bin/mv -n '/Library/PrivilegedHelperTools/x' '/T/x'"
        ])
    }

    @Test func busyTrashNameGetsAStamp() {
        let busy = URL(filePath: "/T/x.plist")
        let destination = LeftoverRemover.trashDestination(
            for: URL(filePath: "/Library/LaunchDaemons/x.plist"), in: Self.userTrash,
            exists: { $0 == busy }, stamp: "14.05.09")
        #expect(destination.path == "/T/x 14.05.09.plist")
        let free = LeftoverRemover.trashDestination(
            for: URL(filePath: "/Library/LaunchDaemons/x.plist"), in: Self.userTrash,
            exists: { _ in false }, stamp: "14.05.09")
        #expect(free.path == "/T/x.plist")
    }

    @Test func userItemsGoToTrashAndAgentsStopFirst() {
        let recorder = Recorder()
        let agent = Self.item("/U/LaunchAgents/a.plist", domain: .user, folder: .launchAgents)
        let cache = Self.item("/U/Caches/a", domain: .user, folder: .caches)
        let report = LeftoverRemover.remove([agent, cache], environment: Self.environment(recorder: recorder))
        #expect(recorder.calls == ["bootout /U/LaunchAgents/a.plist", "trash /U/LaunchAgents/a.plist", "trash /U/Caches/a"])
        #expect(report.removed == [agent.id, cache.id])
        #expect(report.failed.isEmpty)
        #expect(!report.adminCancelled)
    }

    @Test func cancelledPasswordKeepsSystemItems() {
        let recorder = Recorder()
        let user = Self.item("/U/Caches/a", domain: .user, folder: .caches, size: 10)
        let system = Self.item("/Library/Caches/a", domain: .system, folder: .caches, size: 20)
        let env = Self.environment(recorder: recorder, privileged: { _ throws(PrivilegedError) in throw .cancelled })
        let report = LeftoverRemover.remove([user, system], environment: env)
        #expect(report.adminCancelled)
        #expect(report.removed == [user.id])
        #expect(report.failed == [system.id])
        #expect(report.bytes == 10)
    }

    @Test func failedTrashIsReported() {
        let recorder = Recorder()
        let first = Self.item("/U/Caches/a", domain: .user, folder: .caches, size: 5)
        let second = Self.item("/U/Caches/b", domain: .user, folder: .caches, size: 7)
        let third = Self.item("/U/Logs/c", domain: .user, folder: .logs, size: 11)
        let env = Self.environment(recorder: recorder, trashFails: ["/U/Caches/b"])
        let report = LeftoverRemover.remove([first, second, third], environment: env)
        #expect(report.failed == [second.id])
        #expect(report.removed == [first.id, third.id])
        #expect(report.bytes == 16)
    }

    @Test func systemItemStillThereIsFailed() {
        let recorder = Recorder()
        let gone = Self.item("/Library/Caches/a", domain: .system, folder: .caches, size: 3)
        let stuck = Self.item("/Library/Caches/b", domain: .system, folder: .caches, size: 4)
        let env = Self.environment(recorder: recorder, exists: { $0.path == "/Library/Caches/b" })
        let report = LeftoverRemover.remove([gone, stuck], environment: env)
        #expect(report.removed == [gone.id])
        #expect(report.failed == [stuck.id])
        #expect(report.bytes == 3)
        #expect(!report.adminCancelled)
        #expect(recorder.calls == ["privileged"])
    }

    @Test func sameNamedSystemItemsGetDistinctDestinations() {
        let recorder = Recorder()
        let first = Self.item("/Library/Caches/x.log", domain: .system, folder: .caches)
        let second = Self.item("/Library/Logs/x.log", domain: .system, folder: .logs)
        let third = Self.item("/Library/Application Support/x.log", domain: .system, folder: .applicationSupport)
        let scripts = Recorder()
        let env = Self.environment(recorder: recorder, privileged: { script throws(PrivilegedError) in scripts.add(script) })
        _ = LeftoverRemover.remove([first, second, third], environment: env)
        let lines = (scripts.calls.first ?? "").split(separator: "\n").map(String.init)
        #expect(lines == [
            "/bin/mv -n '/Library/Caches/x.log' '/T/x.log'",
            "/bin/mv -n '/Library/Logs/x.log' '/T/x 14.05.09.log'",
            "/bin/mv -n '/Library/Application Support/x.log' '/T/x 14.05.09 2.log'"
        ])
    }
}
