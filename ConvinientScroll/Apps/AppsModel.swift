import Combine
import Foundation

enum AppsSection: String, CaseIterable {
    case installed, removed, orphans
}

enum AppsSort {
    case name, size
}

struct AppsRow: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var size: Int64?
}

@MainActor
final class AppsModel: ObservableObject {
    @Published var section: AppsSection = .installed {
        didSet {
            guard section != oldValue else { return }
            selectedID = nil
            items = []
            checked = []
            pendingRemoval = nil
        }
    }

    @Published var query = ""
    @Published var sort: AppsSort = .name
    @Published private(set) var selectedID: String?
    @Published private(set) var items: [LeftoverItem] = []
    @Published var checked: Set<URL> = []
    @Published private(set) var orphans: [OrphanGroup]?
    @Published private(set) var isScanning = false
    @Published private(set) var hasFullDiskAccess: Bool
    @Published var pendingRemoval: [LeftoverItem]?
    @Published private(set) var lastReport: RemovalReport?
    @Published private(set) var isRemoving = false
    @Published private var sizes: [SizeKey: Int64] = [:]

    private(set) var pendingLoad: Task<Void, Never>?
    private(set) var pendingSync: Task<Void, Never>?
    private var sizesRequested = false
    private var isStopped = false
    private struct SizeKey: Hashable {
        var section: AppsSection
        var id: String
    }

    private struct Entry {
        var row: AppsRow
        var searchKeys: [String]
    }

    private let controller: AppsController
    private let settings: AppSettings
    private var forwarding: Set<AnyCancellable> = []

    init(controller: AppsController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
        hasFullDiskAccess = controller.hasFullDiskAccess
        controller.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &forwarding)
        controller.$installed.dropFirst()
            .sink { [weak self] _ in self?.scheduleSync(installedChanged: true) }
            .store(in: &forwarding)
        controller.$removed.dropFirst()
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &forwarding)
    }

    var rows: [AppsRow] {
        let matching = allEntries().filter { entry in
            query.isEmpty || entry.searchKeys.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return Self.sorted(matching.map(\.row), by: sort)
    }

    nonisolated static func sorted(_ rows: [AppsRow], by sort: AppsSort) -> [AppsRow] {
        switch sort {
        case .name:
            return rows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .size:
            return rows.sorted { lhs, rhs in
                switch (lhs.size, rhs.size) {
                case let (left?, right?) where left != right: left > right
                case (_?, nil): true
                case (nil, _?): false
                default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }

    var canClean: Bool {
        guard !cleanableItems().isEmpty else { return false }
        guard let app = selectedApp else { return true }
        return !controller.isRunning(app)
    }

    func cleanableItems() -> [LeftoverItem] {
        items.filter { ($0.kind == .cache || $0.kind == .log) && $0.isAccessible }
    }

    func select(_ id: String?) async {
        let started = section
        selectedID = id
        items = []
        checked = []
        pendingRemoval = nil
        guard let id else { return }
        let loaded = await loadItems(for: id)
        guard selectedID == id, section == started else { return }
        apply(loaded, for: id)
    }

    func focus(bundleID: String) async {
        section = .removed
        await select(bundleID)
    }

    func askToTrashChecked() {
        guard section != .installed else { return }
        let chosen = items.filter { checked.contains($0.id) && $0.isAccessible }
        pendingRemoval = chosen.isEmpty ? nil : chosen
    }

    func askToClean() {
        guard canClean else { return }
        pendingRemoval = cleanableItems()
    }

    func confirmRemoval() async {
        await startRemoval()?.value
    }

    @discardableResult
    func startRemoval() -> Task<Void, Never>? {
        guard !isRemoving, let requested = pendingRemoval else { return nil }
        pendingRemoval = nil
        let confirmed = validated(requested)
        guard !confirmed.isEmpty else { return nil }
        let startedSection = section
        let id = selectedID
        let before = rows
        isRemoving = true
        return Task { await self.finishRemoval(confirmed, section: startedSection, id: id, before: before) }
    }

    private func finishRemoval(_ confirmed: [LeftoverItem], section startedSection: AppsSection, id: String?, before: [AppsRow]) async {
        lastReport = await controller.remove(confirmed)
        isRemoving = false
        if let id { sizes[SizeKey(section: startedSection, id: id)] = nil }
        if startedSection == .orphans {
            orphans = await controller.orphans(hidden: Set(settings.appsHiddenIDs))
        }
        if section == startedSection, selectedID == id, let id {
            if allEntries().contains(where: { $0.row.id == id }) {
                await select(id)
            } else {
                moveSelection(after: before, from: id)
                await pendingLoad?.value
            }
        }
        await refreshSizes()
    }

    func keepSelected() {
        guard section == .removed, let id = selectedID,
              let entry = controller.removed.first(where: { $0.id == id }) else { return }
        let before = rows
        controller.keep(entry)
        moveSelection(after: before, from: id)
    }

    func hideSelected() {
        guard section == .orphans, let id = selectedID else { return }
        let before = rows
        if !settings.appsHiddenIDs.contains(id) { settings.appsHiddenIDs.append(id) }
        orphans?.removeAll { $0.id == id }
        moveSelection(after: before, from: id)
    }

    func unhide(_ id: String) {
        settings.appsHiddenIDs.removeAll { $0 == id }
    }

    func scanOrphans() async {
        isScanning = true
        orphans = await controller.orphans(hidden: Set(settings.appsHiddenIDs))
        isScanning = false
    }

    func refreshAccess() {
        let granted = controller.hasFullDiskAccess
        guard granted != hasFullDiskAccess else { return }
        hasFullDiskAccess = granted
        let id = selectedID
        let previous = pendingLoad
        pendingLoad = Task {
            await previous?.value
            if self.section == .orphans, self.orphans != nil { await self.scanOrphans() }
            guard self.selectedID == id else { return }
            await self.select(id)
        }
    }

    func stop() {
        isStopped = true
        sizesRequested = false
        forwarding.removeAll()
        pendingLoad?.cancel()
        pendingSync?.cancel()
    }

    func loadSizes() async {
        guard !isStopped else { return }
        sizesRequested = true
        let current = section
        let unsized = allEntries().map(\.row.id).filter { sizes[SizeKey(section: current, id: $0)] == nil }
        guard !unsized.isEmpty else { return }
        let snapshot = current == .orphans ? nil : await controller.librarySnapshot()
        for id in unsized {
            guard section == current, !Task.isCancelled, !isStopped else { return }
            guard let size = await size(of: id, in: snapshot) else { continue }
            guard section == current, !Task.isCancelled, !isStopped else { return }
            sizes[SizeKey(section: current, id: id)] = size
        }
    }

    private func refreshSizes() async {
        if sizesRequested { await loadSizes() }
    }

    private func scheduleSync(installedChanged: Bool = false) {
        let previous = pendingSync
        pendingSync = Task {
            await previous?.value
            await self.syncWithController(installedChanged: installedChanged)
        }
    }

    private func syncWithController(installedChanged: Bool) async {
        let selectedGroupChanged = pruneOrphans()
        let reloadsRemoved = installedChanged && section == .removed
        if let id = selectedID, !allEntries().contains(where: { $0.row.id == id }) {
            await select(rows.first?.id)
        } else if selectedID == nil, let first = rows.first?.id {
            await select(first)
        } else if selectedGroupChanged || reloadsRemoved {
            await select(selectedID)
        }
        await refreshSizes()
    }

    private func pruneOrphans() -> Bool {
        guard let groups = orphans else { return false }
        let kept = OrphanGrouper.pruned(groups, installed: controller.installed)
        guard kept != groups else { return false }
        orphans = kept
        let changed = groups.filter { !kept.contains($0) }.map(\.id)
        for id in changed { sizes[SizeKey(section: .orphans, id: id)] = nil }
        guard section == .orphans, let id = selectedID else { return false }
        return changed.contains(id)
    }

    private func validated(_ items: [LeftoverItem]) -> [LeftoverItem] {
        let accessible = items.filter(\.isAccessible)
        guard section == .installed else { return accessible }
        if let app = selectedApp, controller.isRunning(app) { return [] }
        return accessible.filter { $0.kind == .cache || $0.kind == .log }
    }

    private var selectedApp: InstalledApp? {
        guard let id = selectedID else { return nil }
        return app(for: id)
    }

    private func app(for id: String) -> InstalledApp? {
        switch section {
        case .installed: controller.installed.first { $0.path == id }
        case .removed: controller.removed.first { $0.id == id }?.app
        case .orphans: nil
        }
    }

    private func allEntries() -> [Entry] {
        switch section {
        case .installed:
            controller.installed.map { app in
                Entry(
                    row: AppsRow(
                        id: app.path, title: app.name,
                        subtitle: controller.isRunning(app) ? "Running · \(app.folder)" : app.folder,
                        size: sizes[SizeKey(section: .installed, id: app.path)]),
                    searchKeys: [app.name, app.bundleID])
            }
        case .removed:
            controller.removed.map { entry in
                let when = RelativeDateTimeFormatter().localizedString(for: entry.removedAt, relativeTo: Date())
                return Entry(
                    row: AppsRow(
                        id: entry.id, title: entry.app.name, subtitle: "Removed \(when)",
                        size: sizes[SizeKey(section: .removed, id: entry.id)]),
                    searchKeys: [entry.app.name, entry.id])
            }
        case .orphans:
            (orphans ?? []).map {
                Entry(
                    row: AppsRow(id: $0.id, title: $0.id, subtitle: $0.id, size: sizes[SizeKey(section: .orphans, id: $0.id)]),
                    searchKeys: [$0.id])
            }
        }
    }

    private func loadItems(for id: String) async -> [LeftoverItem] {
        switch section {
        case .installed, .removed:
            guard let app = app(for: id) else { return [] }
            return await controller.leftovers(for: app)
        case .orphans:
            let group = orphans?.first { $0.id == id }
            return await Self.withSizes(group?.items ?? [])
        }
    }

    private func apply(_ loaded: [LeftoverItem], for id: String) {
        items = loaded
        switch section {
        case .installed:
            checked = []
        case .removed:
            checked = Set(loaded.filter(\.isSelectedByDefault).map(\.id))
        case .orphans:
            let defaults = orphans?.first { $0.id == id }?.checkedByDefault ?? []
            checked = Set(loaded.map(\.id)).intersection(defaults)
        }
    }

    private func moveSelection(after before: [AppsRow], from id: String) {
        let index = before.firstIndex { $0.id == id } ?? 0
        let alive = Set(rows.map(\.id))
        let following = before.dropFirst(index + 1) + before.prefix(index).reversed()
        let next = following.first { alive.contains($0.id) }?.id
        selectedID = next
        items = []
        checked = []
        pendingLoad = Task { await self.select(next) }
    }

    private func size(of id: String, in snapshot: LibrarySnapshot?) async -> Int64? {
        switch section {
        case .installed:
            guard let app = app(for: id), let snapshot else { return nil }
            let leftovers = await controller.leftovers(for: app, in: snapshot)
            let own = await Task.detached(priority: .utility) { LibraryScanner.size(of: URL(filePath: app.path)) }.value
            return own + leftovers.compactMap(\.size).reduce(0, +)
        case .removed:
            guard let app = app(for: id), let snapshot else { return nil }
            return await controller.leftovers(for: app, in: snapshot).compactMap(\.size).reduce(0, +)
        case .orphans:
            guard let group = orphans?.first(where: { $0.id == id }) else { return nil }
            return await Self.withSizes(group.items).compactMap(\.size).reduce(0, +)
        }
    }

    private nonisolated static func withSizes(_ items: [LeftoverItem]) async -> [LeftoverItem] {
        await Task.detached(priority: .utility) {
            items.map { item in
                var sized = item
                if item.size == nil, item.isAccessible { sized.size = LibraryScanner.size(of: item.entry.url) }
                return sized
            }
        }.value
    }
}
