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
    @Published private var sizes: [String: Int64] = [:]

    private(set) var pendingLoad: Task<Void, Never>?
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
    }

    var rows: [AppsRow] {
        let all = allRows().filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .name:
            return all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .size:
            return all.sorted { lhs, rhs in
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
        selectedID = id
        items = []
        checked = []
        guard let id else { return }
        let loaded = await loadItems(for: id)
        guard selectedID == id else { return }
        apply(loaded)
    }

    func focus(bundleID: String) async {
        section = .removed
        await select(bundleID)
    }

    func askToTrashChecked() {
        let chosen = items.filter { checked.contains($0.id) }
        pendingRemoval = chosen.isEmpty ? nil : chosen
    }

    func askToClean() {
        let chosen = cleanableItems()
        pendingRemoval = chosen.isEmpty ? nil : chosen
    }

    func confirmRemoval() async {
        guard let confirmed = pendingRemoval else { return }
        pendingRemoval = nil
        let before = rows
        let id = selectedID
        lastReport = await controller.remove(confirmed)
        if let id { sizes[id] = nil }
        if section == .orphans {
            orphans = await controller.orphans(hidden: Set(settings.appsHiddenIDs))
        }
        await reload(after: before, selected: id)
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
        hasFullDiskAccess = controller.hasFullDiskAccess
    }

    func loadSizes() async {
        let current = section
        for row in rows where sizes[row.id] == nil {
            guard section == current else { return }
            guard let size = await size(of: row.id) else { continue }
            guard section == current else { return }
            sizes[row.id] = size
        }
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

    private func allRows() -> [AppsRow] {
        switch section {
        case .installed:
            controller.installed.map { app in
                AppsRow(
                    id: app.path, title: app.name,
                    subtitle: controller.isRunning(app) ? "Running · \(app.folder)" : app.folder,
                    size: sizes[app.path])
            }
        case .removed:
            controller.removed.map { entry in
                let when = RelativeDateTimeFormatter().localizedString(for: entry.removedAt, relativeTo: Date())
                return AppsRow(id: entry.id, title: entry.app.name, subtitle: "Removed \(when)", size: sizes[entry.id])
            }
        case .orphans:
            (orphans ?? []).map { AppsRow(id: $0.id, title: $0.id, subtitle: $0.id, size: sizes[$0.id]) }
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

    private func apply(_ loaded: [LeftoverItem]) {
        items = loaded
        checked = section == .installed ? [] : Set(loaded.filter(\.isSelectedByDefault).map(\.id))
    }

    private func reload(after before: [AppsRow], selected id: String?) async {
        guard let id else { return }
        if rows.contains(where: { $0.id == id }) {
            await select(id)
        } else {
            moveSelection(after: before, from: id)
            await pendingLoad?.value
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

    private func size(of id: String) async -> Int64? {
        switch section {
        case .installed:
            guard let app = app(for: id) else { return nil }
            let leftovers = await controller.leftovers(for: app)
            let own = await Task.detached(priority: .utility) { LibraryScanner.size(of: URL(filePath: app.path)) }.value
            return own + leftovers.compactMap(\.size).reduce(0, +)
        case .removed:
            guard let app = app(for: id) else { return nil }
            return await controller.leftovers(for: app).compactMap(\.size).reduce(0, +)
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
