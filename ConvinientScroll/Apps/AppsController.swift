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
        let library = environment.library(hasFullDiskAccess)
        let installed = installed
        return await Task.detached(priority: .utility) {
            library.leftovers(of: app, installed: installed)
        }.value
    }

    func orphans(hidden: Set<String>) async -> [OrphanGroup] {
        let library = environment.library(hasFullDiskAccess)
        let installed = installed
        return await Task.detached(priority: .utility) {
            library.orphans(installed: installed, hidden: hidden)
        }.value
    }

    func remove(_ items: [LeftoverItem]) async -> RemovalReport {
        let removal = environment.removal
        let installed = installed
        let candidates = removed.map(\.app) + installed
        let (report, owners) = await Task.detached(priority: .userInitiated) {
            let owners = candidates.filter { app in
                items.contains { LeftoverMatcher.match($0.entry, app: app, installed: installed) != nil }
            }.map(\.bundleID)
            return (LeftoverRemover.remove(items, environment: removal), owners)
        }.value
        log(report, count: items.count, owners: owners)
        for entry in removed where owners.contains(entry.id) {
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
            let current = scanner.scan(reusing: index ?? [])
            store.saveIndex(current)
            return (store.loadRemoved(), index, current)
        }.value
        guard isEnabled else { return }
        removed = savedRemoved
        publish(current)
        startWatching(known: index ?? current)
        tracker?.update(current: current)
    }

    private func rescan() async {
        let store = environment.store
        let scanner = environment.scanner
        let previous = installed
        let current = await Task.detached(priority: .utility) {
            let current = scanner.scan(reusing: previous)
            store.saveIndex(current)
            return current
        }.value
        guard isEnabled else { return }
        publish(current)
        tracker?.update(current: current)
    }

    private func publish(_ current: [InstalledApp]) {
        installed = current
        let ids = Set(current.map(\.bundleID))
        let kept = removed.filter { !ids.contains($0.id) }
        guard kept.count != removed.count else { return }
        removed = kept
        environment.store.saveRemoved(kept)
    }

    private func startWatching(known: [InstalledApp]) {
        guard isEnabled, watchEnabled, tracker == nil else { return }
        tracker = RemovalTracker(known: known, schedule: environment.schedule) { [weak self] app in
            guard let self else { return }
            self.enqueue { await self.handleRemoval(of: app) }
        }
        environment.watcher.start(environment.scanner.roots) { [weak self] in
            guard let self else { return }
            self.enqueue { await self.rescan() }
        }
    }

    private func stopWatching() {
        environment.watcher.stop()
        tracker?.cancelAll()
        tracker = nil
    }

    private func handleRemoval(of app: InstalledApp) async {
        guard isEnabled, watchEnabled, !removed.contains(where: { $0.id == app.bundleID }) else { return }
        removed.append(RemovedApp(app: app, removedAt: environment.now()))
        environment.store.saveRemoved(removed)
        let items = await leftovers(for: app)
        guard !items.isEmpty else {
            drop(app.bundleID)
            return
        }
        let bytes = items.compactMap(\.size).reduce(0, +)
        environment.notify(
            app.bundleID,
            LeftoverNotice.title(name: app.name, size: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)),
            LeftoverNotice.body(count: items.count, hasService: items.contains { $0.kind == .service })
        )
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
