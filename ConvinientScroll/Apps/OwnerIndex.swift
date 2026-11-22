import Foundation

nonisolated struct OwnerIndex: Sendable {
    private var byID: [String: Set<String>] = [:]
    private var byTeam: [String: Set<String>] = [:]
    private var byName: [String: Set<String>] = [:]

    init(_ apps: [InstalledApp], alsoOwned extraIDs: [String] = []) {
        for app in apps {
            for id in app.ownedIDs where !id.isEmpty {
                byID[id.lowercased(), default: []].insert(app.path)
            }
            if let team = app.teamID, !team.isEmpty {
                byTeam[team.lowercased(), default: []].insert(app.path)
            }
            for name in app.matchNames {
                byName[name.lowercased(), default: []].insert(app.path)
            }
        }
        for id in extraIDs where !id.isEmpty {
            byID[id.lowercased(), default: []].insert("")
        }
    }

    func owns(_ entry: LibraryEntry) -> Bool {
        let name = entry.name.lowercased()
        if entry.folder == .groupContainers, !teamOwners(ofContainer: name).isEmpty { return true }
        if !bundleIDOwners(of: name).isEmpty { return true }
        guard let id = LeftoverMatcher.entryID(entry.name, folder: entry.folder) else { return false }
        return !bundleIDOwners(of: id.lowercased()).isEmpty
    }

    func bundleIDOwners(of lowerName: String) -> Set<String> {
        var result = owners(in: byID, prefixesOf: lowerName, includingWhole: true)
        if lowerName.hasPrefix("group.") {
            result.formUnion(owners(in: byID, prefixesOf: String(lowerName.dropFirst("group.".count)), includingWhole: true))
        }
        return result
    }

    func teamOwners(ofContainer lowerName: String) -> Set<String> {
        owners(in: byTeam, prefixesOf: lowerName, includingWhole: false)
    }

    func hasOtherApp(withTeam lowerTeam: String, than path: String) -> Bool {
        byTeam[lowerTeam]?.contains { $0 != path } ?? false
    }

    func nameOwners(_ lowerName: String) -> Set<String> {
        byName[lowerName] ?? []
    }

    private func owners(in table: [String: Set<String>], prefixesOf name: String, includingWhole: Bool) -> Set<String> {
        var result = includingWhole ? table[name] ?? [] : []
        var index = name.startIndex
        while let dot = name[index...].firstIndex(of: ".") {
            if let found = table[String(name[..<dot])] { result.formUnion(found) }
            index = name.index(after: dot)
        }
        return result
    }
}
