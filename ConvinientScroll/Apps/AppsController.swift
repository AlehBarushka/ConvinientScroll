import AppKit
import Combine
import OSLog

struct AppsEnvironment {
    var store: AppsStore
    var scanner: AppScanner
    var library: (_ canReadProtected: Bool) -> LibraryScanner
    var watcher: FolderWatching
    var schedule: RemovalTracker.Schedule
    var notify: (_ bundleID: String, _ title: String, _ body: String) -> Void
    var removal: RemovalEnvironment
    var hasFullDiskAccess: () -> Bool
    var isRunning: (String) -> Bool
    var appLocations: (String) -> [URL]
    var ownBundleID: String?
    var now: () -> Date

    static func live() -> AppsEnvironment {
        AppsEnvironment(
            store: AppsStore(root: AppsStore.defaultRoot),
            scanner: .live,
            library: { LibraryScanner.live(canReadProtected: $0) },
            watcher: ApplicationsWatcher(),
            schedule: { delay, action in
                let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                return AnyCancellable { item.cancel() }
            },
            notify: { NotificationService.shared.showLeftovers(bundleID: $0, title: $1, body: $2) },
            removal: .live(),
            hasFullDiskAccess: FullDiskAccess.isGranted,
            isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
            appLocations: { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) },
            ownBundleID: Bundle.main.bundleIdentifier,
            now: Date.init
        )
    }
}

@MainActor
final class AppsController: ObservableObject {
    @Published private(set) var installed: [InstalledApp] = []
    @Published private(set) var removed: [RemovedApp] = []

    var watchEnabled = true {
        didSet {
            guard watchEnabled != oldValue, isEnabled else { return }
            if watchEnabled {
                enqueue {
                    await self.rescan()
                    self.startWatching(known: self.installed)
                }
            } else {
                stopWatching()
            }
        }
    }

    var hasFullDiskAccess: Bool { environment.hasFullDiskAccess() }

    private(set) var pendingWork: Task<Void, Never>?
    private let environment: AppsEnvironment
    private var isEnabled = false
    private var tracker: RemovalTracker?
    private var owners = OwnerIndex([])
    private var savedIndex: [InstalledApp]?

    init(environment: AppsEnvironment) {
        self.environment = environment
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            await enqueue { await self.start() }.value
        } else {
            stopWatching()
        }
    }

    func refreshInstalled() async {
        await enqueue { await self.rescan() }.value
    }

    func leftovers(for app: InstalledApp) async -> [LeftoverItem] {
        await leftovers(for: app, in: librarySnapshot())
    }

    func librarySnapshot() async -> LibrarySnapshot {
        let library = environment.library(hasFullDiskAccess)
        let owners = owners
        let entries = await Task.detached(priority: .utility) { library.entries() }.value
        return LibrarySnapshot(library: library, entries: entries, owners: owners)
    }

    func leftovers(for app: InstalledApp, in snapshot: LibrarySnapshot) async -> [LeftoverItem] {
        await Task.detached(priority: .utility) {
            snapshot.library.leftovers(of: app, in: snapshot.entries, owners: snapshot.owners)
        }.value
    }

    func orphans(hidden: Set<String>) async -> [OrphanGroup] {
        let library = environment.library(hasFullDiskAccess)
        let installed = installed
        let ownIDs = environment.ownBundleID.map { [$0] } ?? []
        return await Task.detached(priority: .utility) {
            library.orphans(installed: installed, hidden: hidden, alsoOwned: ownIDs)
        }.value
    }

    func remove(_ items: [LeftoverItem]) async -> RemovalReport {
        let removal = environment.removal
        let owners = owners
        let allowed = items.filter { item in
            item.kind == .cache || item.kind == .log || !(owners.owns(item.entry) || owners.ownsByName(item.entry))
        }
        if allowed.count < items.count {
            AppLog.apps.notice("Skipped \(items.count - allowed.count) items that belong to an installed app")
        }
        let candidates = removed.map(\.app) + installed
        let (report, ownerIDs) = await Task.detached(priority: .userInitiated) {
            let ownerIDs = candidates.filter { app in
                allowed.contains { LeftoverMatcher.match($0.entry, app: app, owners: owners) != nil }
            }.map(\.bundleID)
            return (LeftoverRemover.remove(allowed, environment: removal), ownerIDs)
        }.value
        log(report, count: items.count, owners: ownerIDs)
        for entry in removed where ownerIDs.contains(entry.id) {
            if await leftovers(for: entry.app).isEmpty { drop(entry.id) }
        }
        return report
    }

    func keep(_ app: RemovedApp) {
        drop(app.id)
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        environment.isRunning(app.bundleID)
    }

    @discardableResult
    private func enqueue(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = pendingWork
        let task = Task {
            await previous?.value
            await work()
        }
        pendingWork = task
        return task
    }

    private func start() async {
        let store = environment.store
        let scanner = environment.scanner
        let (savedRemoved, index, current) = await Task.detached(priority: .utility) {
            let index = store.loadIndex()
            return (store.loadRemoved(), index, scanner.scan(reusing: index ?? []))
        }.value
        guard isEnabled else { return }
        removed = savedRemoved
        savedIndex = index
        startWatching(known: index ?? current)
        guard !scanFailed(current) else { return }
        publish(current)
        tracker?.update(current: current)
        await saveIndex()
    }

    private func rescan() async {
        let scanner = environment.scanner
        let previous = installed
        let current = await Task.detached(priority: .utility) {
            scanner.scan(reusing: previous)
        }.value
        guard isEnabled, !scanFailed(current) else { return }
        publish(current)
        tracker?.update(current: current)
        await saveIndex()
    }

    private func scanFailed(_ current: [InstalledApp]) -> Bool {
        guard current.isEmpty, let known = tracker?.known, !known.isEmpty else { return false }
        AppLog.apps.error("App scan found no apps while \(known.count) were known; keeping the previous list")
        return true
    }

    private func saveIndex() async {
        let store = environment.store
        let apps = installed + (tracker?.pendingApps ?? [])
        guard apps != savedIndex else { return }
        let saved = await Task.detached(priority: .utility) {
            store.saveIndex(apps)
        }.value
        if saved { savedIndex = apps }
    }

    private func publish(_ current: [InstalledApp]) {
        if installed != current {
            installed = current
            owners = OwnerIndex(current)
        }
        let ids = Set(current.map(\.bundleID))
        let kept = removed.filter { !ids.contains($0.id) }
        guard kept.count != removed.count else { return }
        removed = kept
        environment.store.saveRemoved(kept)
    }

    private func startWatching(known: [InstalledApp]) {
        guard isEnabled, watchEnabled, tracker == nil else { return }
        let schedule = environment.schedule
        let checkThenSave: RemovalTracker.Schedule = { [weak self] delay, action in
            schedule(delay) {
                action()
                guard let self else { return }
                self.enqueue { await self.saveIndex() }
            }
        }
        tracker = RemovalTracker(known: known, schedule: checkThenSave) { [weak self] app in
            guard let self else { return }
            self.enqueue { await self.handleRemoval(of: app) }
        }
        environment.watcher.start(environment.scanner.roots) { [weak self] paths in
            guard let self, ApplicationsWatcher.canChangeAppList(paths, installed: Set(self.installed.map(\.path))) else { return }
            self.enqueue { await self.rescan() }
        }
    }

    private func stopWatching() {
        environment.watcher.stop()
        let hadCandidates = !(tracker?.pendingApps.isEmpty ?? true)
        tracker?.cancelAll()
        tracker = nil
        if hadCandidates {
            enqueue { await self.saveIndex() }
        }
    }

    private func handleRemoval(of app: InstalledApp) async {
        guard isEnabled, watchEnabled,
              app.bundleID != environment.ownBundleID,
              !installed.contains(where: { $0.bundleID == app.bundleID }),
              !removed.contains(where: { $0.id == app.bundleID })
        else { return }
        if let moved = environment.appLocations(app.bundleID).first(where: isElsewhere) {
            AppLog.apps.info("\(app.bundleID, privacy: .public) moved to \(moved.path, privacy: .private)")
            return
        }
        removed.append(RemovedApp(app: app, removedAt: environment.now()))
        environment.store.saveRemoved(removed)
        let items = await leftovers(for: app)
        guard removed.contains(where: { $0.id == app.bundleID }) else { return }
        guard !items.isEmpty else {
            drop(app.bundleID)
            return
        }
        guard isEnabled, watchEnabled else { return }
        let bytes = items.compactMap(\.size).reduce(0, +)
        environment.notify(
            app.bundleID,
            LeftoverNotice.title(name: app.name, size: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)),
            LeftoverNotice.body(count: items.count, hasService: items.contains { $0.kind == .service })
        )
    }

    private func isElsewhere(_ url: URL) -> Bool {
        let trash = environment.removal.userTrash.standardizedFileURL.path + "/"
        return !url.standardizedFileURL.path.hasPrefix(trash) && environment.removal.exists(url)
    }

    private func drop(_ bundleID: String) {
        removed.removeAll { $0.id == bundleID }
        environment.store.saveRemoved(removed)
    }

    private func log(_ report: RemovalReport, count: Int, owners: [String]) {
        let owner = owners.isEmpty ? "no installed or removed app" : owners.joined(separator: ", ")
        let size = ByteCountFormatter.string(fromByteCount: report.bytes, countStyle: .file)
        AppLog.apps.notice("Moved \(report.removed.count) of \(count) items (\(size, privacy: .public)) of \(owner, privacy: .public) to the Trash")
        for url in report.failed {
            AppLog.apps.error("Not moved to the Trash: \(url.path, privacy: .private)")
        }
        if report.adminCancelled {
            AppLog.apps.notice("Administrator password was not given; files in /Library stay")
        }
    }
}
