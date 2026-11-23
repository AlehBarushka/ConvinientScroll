import Combine
import Foundation
import Testing
@testable import MacToolkit

@MainActor final class FakeWatcher: FolderWatching {
    private(set) var folders: [URL]?
    var onChange: (([String]) -> Void)?

    var isWatching: Bool { onChange != nil }

    func start(_ folders: [URL], onChange: @escaping ([String]) -> Void) {
        self.folders = folders
        self.onChange = onChange
    }

    func stop() { onChange = nil }

    func fire(_ paths: [String] = []) { onChange?(paths) }
}

@MainActor final class AppsScheduler {
    final class Check {
        let action: () -> Void
        var cancelled = false
        init(action: @escaping () -> Void) { self.action = action }
    }

    private(set) var checks: [Check] = []

    var schedule: RemovalTracker.Schedule {
        { _, action in
            let check = Check(action: action)
            self.checks.append(check)
            return AnyCancellable { check.cancelled = true }
        }
    }

    func runPending() {
        let due = checks.filter { !$0.cancelled }
        checks.removeAll()
        due.forEach { $0.action() }
    }
}

struct Notice: Equatable {
    var bundleID: String
    var title: String
    var body: String
}

@MainActor final class Notices {
    var calls: [Notice] = []
}

@MainActor final class RunningApps {
    var ids: Set<String> = []
}

@MainActor final class AccessState {
    var granted = true
}

@MainActor final class AppLocations {
    var urls: [String: [URL]] = [:]
}

@MainActor final class SearchHook {
    var beforeSearch: (() -> Void)?
}

@MainActor struct Sandbox {
    let root = FileManager.default.temporaryDirectory.appending(path: "AppsControllerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let watcher = FakeWatcher()
    let scheduler = AppsScheduler()
    let notices = Notices()
    let searchHook = SearchHook()
    let running = RunningApps()
    let access = AccessState()
    let locations = AppLocations()
    let ownBundleID = "com.example.toolkit"

    var apps: URL { root.appending(path: "Applications", directoryHint: .isDirectory) }
    var user: URL { root.appending(path: "User", directoryHint: .isDirectory) }
    var system: URL { root.appending(path: "System", directoryHint: .isDirectory) }
    var trash: URL { root.appending(path: "Trash", directoryHint: .isDirectory) }
    var store: AppsStore { AppsStore(root: root.appending(path: "Store", directoryHint: .isDirectory)) }

    init() throws {
        for folder in [apps, user, system] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func makeController() -> AppsController {
        let user = user, system = system, notices = notices, searchHook = searchHook, running = running, access = access,
            locations = locations
        return AppsController(environment: AppsEnvironment(
            store: store,
            scanner: AppScanner(roots: [apps], teamID: { _ in nil }),
            library: {
                searchHook.beforeSearch?()
                return LibraryScanner(userLibrary: user, systemLibrary: system, canReadProtected: $0)
            },
            watcher: watcher,
            schedule: scheduler.schedule,
            notify: { notices.calls.append(Notice(bundleID: $0, title: $1, body: $2)) },
            removal: RemovalEnvironment(
                trash: { try FileManager.default.removeItem(at: $0) },
                bootoutUser: { _ in },
                runPrivileged: { _ throws(PrivilegedError) in },
                exists: { FileManager.default.fileExists(atPath: $0.path) },
                userTrash: trash,
                owner: "501:20",
                now: { Date(timeIntervalSince1970: 0) }),
            hasFullDiskAccess: { access.granted },
            isRunning: { running.ids.contains($0) },
            appLocations: { locations.urls[$0] ?? [] },
            ownBundleID: ownBundleID,
            now: { Date(timeIntervalSince1970: 1_000) }
        ))
    }

    @discardableResult
    func installApp(_ name: String, id: String, fileName: String? = nil) throws -> URL {
        let bundle = apps.appending(path: "\(fileName ?? name).app", directoryHint: .isDirectory)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    func indexedApp(_ name: String, id: String) -> InstalledApp {
        InstalledApp(
            path: apps.appending(path: "\(name).app").path, bundleID: id, name: name, executable: nil, version: nil,
            teamID: nil, nestedBundleIDs: [], infoPlistModified: Date(timeIntervalSince1970: 0))
    }

    func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }
}
