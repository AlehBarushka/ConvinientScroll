import Foundation
import AppKit
import Combine
import OSLog

/// Keeps the shelf's files and their index on disk. All file I/O runs off the main
/// thread; the published state changes on the main actor.
@MainActor
final class ShelfStore: ObservableObject {
    struct Configuration: Sendable {
        var rootURL: URL
        /// A file from another volume above this size is kept as a link, not copied.
        var referenceThreshold: Int64 = 1 << 30
        var isSameVolume: @Sendable (URL, URL) -> Bool = ShelfFiles.isSameVolume
        /// Off in tests, which call `purgeExpired()` themselves.
        var schedulesPurge = true
    }

    nonisolated static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.alehbarushka.convinientscroll"
        return base.appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "Shelf", directoryHint: .isDirectory)
    }

    /// Oldest first.
    @Published private(set) var items: [ShelfItem] = []
    /// Links whose original cannot be reached (deleted, or its disk ejected).
    @Published private(set) var missingItemIDs: Set<UUID> = []
    /// A short message about files that could not be added; cleared after a few seconds.
    @Published private(set) var failureMessage: String?

    var retention: TimeInterval {
        didSet {
            guard retention != oldValue else { return }
            Task { await purgeExpired() }
        }
    }

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.byteSize }
    }

    private let configuration: Configuration
    private let now: () -> Date
    private var purgeTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var saveTask: Task<Void, Never>?
    private var failureTask: Task<Void, Never>?
    private var pendingIO: [Task<Void, Never>] = []

    private var rootURL: URL { configuration.rootURL }

    init(configuration: Configuration, retention: TimeInterval, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration
        self.retention = retention
        self.now = now
        if configuration.schedulesPurge {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.purgeExpired() }
                }
            }
        }
    }

    /// Reads the index and removes leftovers of interrupted copies.
    func load() async {
        let loaded = await ShelfFiles.loadIndex(root: rootURL)
        // Files dropped while the index was loading stay too.
        let known = Set(loaded.map(\.id))
        items = loaded + items.filter { !known.contains($0.id) }
        await purgeExpired()
        refreshAvailability()
    }

    /// Copies (or links) the files; returns what was added.
    @discardableResult
    func add(_ urls: [URL]) async -> [ShelfItem] {
        let ownPrefix = rootURL.standardizedFileURL.path + "/"
        // Dragging a card back onto the shelf must not duplicate it.
        let sources = urls.filter { !$0.standardizedFileURL.path.hasPrefix(ownPrefix) }
        guard !sources.isEmpty else { return [] }

        var added: [ShelfItem] = []
        var failed: [String] = []
        for url in sources {
            do {
                let item = try await ShelfFiles.makeItem(
                    from: url,
                    root: rootURL,
                    threshold: configuration.referenceThreshold,
                    isSameVolume: configuration.isSameVolume,
                    addedAt: now()
                )
                added.append(item)
            } catch {
                failed.append(url.lastPathComponent)
                AppLog.shelf.error("Cannot add \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
            }
        }

        items.append(contentsOf: added)
        if !failed.isEmpty {
            showFailure(failed.count == 1 ? "Couldn’t add “\(failed[0])”" : "Couldn’t add \(failed.count) files")
        }
        if !added.isEmpty {
            scheduleSave()
            reschedulePurge()
        }
        return added
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        missingItemIDs.remove(id)
        deleteFiles(of: [item])
    }

    func removeAll() {
        guard !items.isEmpty else { return }
        let removed = items
        items.removeAll()
        missingItemIDs.removeAll()
        deleteFiles(of: removed)
    }

    func url(for item: ShelfItem) -> URL? {
        switch item.storage {
        case .copy(let relativePath):
            rootURL.appending(path: relativePath)
        case .reference(let bookmark):
            ShelfFiles.resolve(bookmark: bookmark)
        }
    }

    /// Re-checks linked originals; cheap, called when the shelf opens.
    func refreshAvailability() {
        var missing = Set<UUID>()
        for item in items where item.isReference {
            let url = url(for: item)
            if url == nil || (try? url?.checkResourceIsReachable()) != true {
                missing.insert(item.id)
            }
        }
        if missing != missingItemIDs { missingItemIDs = missing }
    }

    func purgeExpired() async {
        let cutoff = now().addingTimeInterval(-retention)
        let expired = items.filter { $0.addedAt <= cutoff }
        if !expired.isEmpty {
            let ids = Set(expired.map(\.id))
            items.removeAll { ids.contains($0.id) }
            missingItemIDs.subtract(ids)
            AppLog.shelf.info("Removed \(expired.count) expired item(s)")
            deleteFiles(of: expired)
        }
        reschedulePurge()
        await waitForPendingIO()
    }

    /// Writes the index now and waits for queued deletions (tests, termination).
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await ShelfFiles.writeIndex(items, root: rootURL)
        await waitForPendingIO()
    }

    // MARK: - Private

    private func deleteFiles(of removed: [ShelfItem]) {
        let root = rootURL
        pendingIO.append(Task { await ShelfFiles.deleteFiles(of: removed, root: root) })
        scheduleSave()
        reschedulePurge()
    }

    private func waitForPendingIO() async {
        while !pendingIO.isEmpty {
            let tasks = pendingIO
            pendingIO.removeAll()
            for task in tasks { await task.value }
        }
    }

    /// Several changes in a row produce one write.
    private func scheduleSave() {
        saveTask?.cancel()
        let root = rootURL
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.items
            self.saveTask = nil
            await ShelfFiles.writeIndex(snapshot, root: root)
        }
    }

    /// One timer for the nearest expiry; none while the shelf is empty.
    private func reschedulePurge() {
        purgeTimer?.invalidate()
        purgeTimer = nil
        guard configuration.schedulesPurge, let oldest = items.map(\.addedAt).min() else { return }
        let fireDate = max(oldest.addingTimeInterval(retention), Date().addingTimeInterval(1))
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.purgeExpired() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    private func showFailure(_ message: String) {
        failureMessage = message
        failureTask?.cancel()
        failureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.failureMessage = nil
        }
    }
}

/// File-system work for the shelf, kept off the main actor.
nonisolated enum ShelfFiles {
    static let indexName = "index.json"
    static let itemsFolder = "items"

    static func isSameVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard
            let a = try? lhs.resourceValues(forKeys: key).volumeIdentifier as? NSObject,
            let b = try? rhs.resourceValues(forKeys: key).volumeIdentifier as? NSObject
        else { return false }
        return a.isEqual(b)
    }

    @concurrent
    static func makeItem(
        from source: URL,
        root: URL,
        threshold: Int64,
        isSameVolume: @Sendable (URL, URL) -> Bool,
        addedAt: Date
    ) async throws -> ShelfItem {
        let fm = FileManager.default
        let itemsRoot = root.appending(path: itemsFolder, directoryHint: .isDirectory)
        try fm.createDirectory(at: itemsRoot, withIntermediateDirectories: true)

        let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        let size = byteSize(of: source, isDirectory: isDirectory)
        let id = UUID()
        let name = source.lastPathComponent

        if size > threshold, !isSameVolume(source, root) {
            let bookmark = try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            return ShelfItem(id: id, displayName: name, addedAt: addedAt, byteSize: size,
                             isDirectory: isDirectory, storage: .reference(bookmark: bookmark))
        }

        let folder = itemsRoot.appending(path: id.uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            // On APFS this is a clone: instant, and it shares blocks with the original.
            try fm.copyItem(at: source, to: folder.appending(path: name))
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
        return ShelfItem(id: id, displayName: name, addedAt: addedAt, byteSize: size,
                         isDirectory: isDirectory,
                         storage: .copy(relativePath: "\(itemsFolder)/\(id.uuidString)/\(name)"))
    }

    static func byteSize(of url: URL, isDirectory: Bool) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard isDirectory else {
            return Int64((try? url.resourceValues(forKeys: keys).fileSize) ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    static func resolve(bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    @concurrent
    static func loadIndex(root: URL) async -> [ShelfItem] {
        let fm = FileManager.default
        var items: [ShelfItem] = []
        if let data = try? Data(contentsOf: root.appending(path: indexName)) {
            do {
                items = try JSONDecoder().decode([ShelfItem].self, from: data)
            } catch {
                AppLog.shelf.error("Shelf index is unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Drop entries whose copy is gone.
        items.removeAll { item in
            guard case .copy(let path) = item.storage else { return false }
            return !fm.fileExists(atPath: root.appending(path: path).path)
        }

        // Remove folders no entry points to (a copy interrupted by a crash).
        let known = Set(items.map(\.id.uuidString))
        let itemsRoot = root.appending(path: itemsFolder, directoryHint: .isDirectory)
        let folders = (try? fm.contentsOfDirectory(at: itemsRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !known.contains(folder.lastPathComponent) {
            try? fm.removeItem(at: folder)
        }
        return items
    }

    @concurrent
    static func writeIndex(_ items: [ShelfItem], root: URL) async {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: root.appending(path: indexName), options: .atomic)
        } catch {
            AppLog.shelf.error("Cannot save the shelf index: \(error.localizedDescription, privacy: .public)")
        }
    }

    @concurrent
    static func deleteFiles(of items: [ShelfItem], root: URL) async {
        let fm = FileManager.default
        for item in items where !item.isReference {
            let folder = root.appending(path: itemsFolder, directoryHint: .isDirectory)
                .appending(path: item.id.uuidString, directoryHint: .isDirectory)
            do {
                try fm.removeItem(at: folder)
            } catch {
                AppLog.shelf.error("Cannot delete a shelf item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
