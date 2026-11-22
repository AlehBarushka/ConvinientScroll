import Foundation

nonisolated struct OrphanGroup: Hashable, Sendable, Identifiable {
    var id: String
    var items: [LeftoverItem]
    var sharesVendorWithInstalledApp = false

    private static let checkedKinds: Set<LeftoverKind> = [.cache, .log, .windowState]

    var checkedByDefault: Set<URL> {
        guard !sharesVendorWithInstalledApp else { return [] }
        return Set(items
            .filter { $0.isAccessible && $0.entry.domain == .user && Self.checkedKinds.contains($0.kind) }
            .map(\.id))
    }
}

nonisolated enum OrphanGrouper {
    static func groups(_ entries: [LibraryEntry], installed: [InstalledApp], hidden: Set<String>, canReadProtected: Bool,
                       alsoOwned: [String] = []) -> [OrphanGroup] {
        let owners = OwnerIndex(installed, alsoOwned: alsoOwned)
        let candidates: [(id: String, entry: LibraryEntry)] = entries.compactMap { entry in
            let name = entry.name
            if LeftoverMatcher.isApple(name) { return nil }
            guard let id = LeftoverMatcher.entryID(name, folder: entry.folder), !LeftoverMatcher.isApple(id) else { return nil }
            if id.lowercased().hasPrefix("homebrew.mxcl.") { return nil }
            if owners.owns(entry) { return nil }
            return (id, entry)
        }
        let ids = Set(candidates.map(\.id))
        let grouped = Dictionary(grouping: candidates) { candidate in
            ids.filter { candidate.id == $0 || candidate.id.hasPrefix($0 + ".") }.min { $0.count < $1.count } ?? candidate.id
        }
        let vendors = vendors(of: installed)
        return grouped
            .filter { !hidden.contains($0.key) }
            .map { id, members in
                let items = members
                    .map { LeftoverItem.make($0.entry, match: .bundleID, canReadProtected: canReadProtected) }
                    .sorted { $0.entry.url.path < $1.entry.url.path }
                return OrphanGroup(id: id, items: items, sharesVendorWithInstalledApp: vendors.contains(vendor(of: id)))
            }
            .sorted { $0.id < $1.id }
    }

    static func pruned(_ groups: [OrphanGroup], installed: [InstalledApp]) -> [OrphanGroup] {
        let owners = OwnerIndex(installed)
        let vendors = vendors(of: installed)
        return groups.compactMap { group in
            var group = group
            group.items.removeAll { owners.owns($0.entry) }
            guard !group.items.isEmpty else { return nil }
            group.sharesVendorWithInstalledApp = vendors.contains(vendor(of: group.id))
            return group
        }
    }

    private static func vendors(of installed: [InstalledApp]) -> Set<String> {
        Set(installed.map { vendor(of: $0.bundleID) })
    }

    private static func vendor(of id: String) -> String {
        id.lowercased().split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false).prefix(2).joined(separator: ".")
    }
}
