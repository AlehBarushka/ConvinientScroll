import Foundation

nonisolated struct LibraryScanner: Sendable {
    var userLibrary: URL
    var systemLibrary: URL
    var canReadProtected: Bool

    static func live(canReadProtected: Bool) -> LibraryScanner {
        LibraryScanner(
            userLibrary: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library"),
            systemLibrary: URL(filePath: "/Library"),
            canReadProtected: canReadProtected)
    }

    func entries() -> [LibraryEntry] {
        let domains: [(LibraryDomain, URL)] = [(.user, userLibrary), (.system, systemLibrary)]
        return domains.flatMap { domain, root in
            LibraryFolder.folders(in: domain).flatMap { folder -> [LibraryEntry] in
                let directory = root.appending(path: folder.rawValue)
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                return urls.map { LibraryEntry(url: $0, domain: domain, folder: folder) }
            }
        }
    }

    func leftovers(of app: InstalledApp, installed: [InstalledApp]) -> [LeftoverItem] {
        leftovers(of: app, in: entries(), owners: OwnerIndex(installed))
    }

    func leftovers(of app: InstalledApp, in entries: [LibraryEntry], owners: OwnerIndex) -> [LeftoverItem] {
        entries
            .compactMap { entry -> LeftoverItem? in
                guard let match = LeftoverMatcher.match(entry, app: app, owners: owners) else { return nil }
                var item = LeftoverItem.make(entry, match: match, canReadProtected: canReadProtected)
                if item.isAccessible { item.size = Self.size(of: entry.url) }
                return item
            }
            .sorted { $0.entry.url.path < $1.entry.url.path }
    }

    func orphans(installed: [InstalledApp], hidden: Set<String>, alsoOwned: [String] = []) -> [OrphanGroup] {
        OrphanGrouper.groups(entries(), installed: installed, hidden: hidden, canReadProtected: canReadProtected, alsoOwned: alsoOwned)
    }

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func allocated(_ url: URL) -> Int64 {
            guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total = allocated(url)
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return total }
        for case let child as URL in walker { total += allocated(child) }
        return total
    }
}

nonisolated struct LibrarySnapshot: Sendable {
    var library: LibraryScanner
    var entries: [LibraryEntry]
    var owners: OwnerIndex
}
