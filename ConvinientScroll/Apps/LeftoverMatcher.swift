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
        let name = entry.name.lowercased()
        if isApple(name) { return nil }
        let others = installed.filter { $0.path != app.path }
        if others.contains(where: { ownsByBundleID($0, name) }) { return nil }
        if ownsByBundleID(app, name) { return .bundleID }
        if entry.folder == .groupContainers, let team = app.teamID?.lowercased(), name.hasPrefix(team + "."),
           !others.contains(where: { $0.teamID?.lowercased() == team }) {
            return .teamID
        }
        if entry.folder.allowsNameMatch {
            let names = Set(app.matchNames.map { $0.lowercased() })
            if names.contains(name), !others.contains(where: { $0.matchNames.contains { names.contains($0.lowercased()) } }) {
                return .name
            }
        }
        return nil
    }

    private static func ownsByBundleID(_ app: InstalledApp, _ lowerName: String) -> Bool {
        app.ownedIDs.contains { id in
            let id = id.lowercased()
            return lowerName == id || lowerName.hasPrefix(id + ".") || lowerName == "group." + id || lowerName.hasPrefix("group." + id + ".")
        }
    }
}
