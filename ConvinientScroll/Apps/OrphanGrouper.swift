import Foundation

nonisolated struct OrphanGroup: Hashable, Sendable, Identifiable {
    var id: String
    var items: [LeftoverItem]
}

nonisolated enum OrphanGrouper {
    static func groups(_ entries: [LibraryEntry], installed: [InstalledApp], hidden: Set<String>, canReadProtected: Bool) -> [OrphanGroup] {
        let ownedIDs = installed.flatMap(\.ownedIDs).map { $0.lowercased() }
        let teams = installed.compactMap { $0.teamID?.lowercased() }
        let candidates: [(id: String, entry: LibraryEntry)] = entries.compactMap { entry in
            let name = entry.name
            if LeftoverMatcher.isApple(name) { return nil }
            if entry.folder == .groupContainers, teams.contains(where: { name.lowercased().hasPrefix($0 + ".") }) { return nil }
            guard let id = LeftoverMatcher.entryID(name, folder: entry.folder), !LeftoverMatcher.isApple(id) else { return nil }
            let lower = id.lowercased()
            if ownedIDs.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) { return nil }
            return (id, entry)
        }
        let ids = Set(candidates.map(\.id))
        let grouped = Dictionary(grouping: candidates) { candidate in
            ids.filter { candidate.id == $0 || candidate.id.hasPrefix($0 + ".") }.min { $0.count < $1.count } ?? candidate.id
        }
        return grouped
            .filter { !hidden.contains($0.key) }
            .map { id, members in
                let items = members
                    .map { LeftoverItem.make($0.entry, match: .bundleID, canReadProtected: canReadProtected) }
                    .sorted { $0.entry.url.path < $1.entry.url.path }
                return OrphanGroup(id: id, items: items)
            }
            .sorted { $0.id < $1.id }
    }
}
