import Foundation

nonisolated enum LeftoverMatcher {
    private static let strippedSuffixes = [".plist", ".savedState", ".binarycookies"]

    static func isApple(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.")
    }

    static func entryID(_ name: String, folder: LibraryFolder) -> String? {
        var id = name
        if let suffix = strippedSuffixes.first(where: { id.lowercased().hasSuffix($0.lowercased()) }) {
            id.removeLast(suffix.count)
        }
        if folder == .groupContainers {
            if id.lowercased().hasPrefix("group.") {
                id.removeFirst("group.".count)
            } else if let range = id.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) {
                id.removeSubrange(range)
            }
        }
        if folder == .preferencesByHost,
           let range = id.range(of: "\\.([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{12})$",
                                options: .regularExpression) {
            id.removeSubrange(range)
        }
        return id.filter { $0 == "." }.count >= 2 ? id : nil
    }

    static func match(_ entry: LibraryEntry, app: InstalledApp, installed: [InstalledApp]) -> MatchKind? {
        match(entry, app: app, owners: OwnerIndex(installed))
    }

    static func match(_ entry: LibraryEntry, app: InstalledApp, owners: OwnerIndex) -> MatchKind? {
        let name = entry.name.lowercased()
        if isApple(name) { return nil }
        let path = app.path
        if owners.bundleIDOwners(of: name).contains(where: { $0 != path }) { return nil }
        let team = app.teamID?.lowercased()
        let teamIsShared = team.map { owners.hasOtherApp(withTeam: $0, than: path) } ?? false
        switch bundleIDMatch(app, name) {
        case .direct:
            return .bundleID
        case .group:
            return entry.folder == .groupContainers && teamIsShared ? nil : .bundleID
        case nil:
            break
        }
        if entry.folder == .groupContainers, let team, name.hasPrefix(team + "."), !teamIsShared {
            return .teamID
        }
        if entry.folder.allowsNameMatch, !app.bundleID.lowercased().hasPrefix("com.apple.") {
            let names = Set(app.matchNames.map { $0.lowercased() })
            if names.contains(name), !names.contains(where: { owners.nameOwners($0).contains { $0 != path } }) {
                return .name
            }
        }
        return nil
    }

    private enum BundleIDMatch {
        case direct, group
    }

    private static func bundleIDMatch(_ app: InstalledApp, _ lowerName: String) -> BundleIDMatch? {
        let ids = app.ownedIDs.filter { !$0.isEmpty }.map { $0.lowercased() }
        if ids.contains(where: { lowerName == $0 || lowerName.hasPrefix($0 + ".") }) { return .direct }
        if ids.contains(where: { lowerName == "group." + $0 || lowerName.hasPrefix("group." + $0 + ".") }) { return .group }
        return nil
    }
}
