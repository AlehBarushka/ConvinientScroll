import Foundation

nonisolated struct InstalledApp: Codable, Hashable, Sendable {
    var path: String
    var bundleID: String
    var name: String
    var executable: String?
    var version: String?
    var teamID: String?
    var nestedBundleIDs: [String]
    var infoPlistModified: Date

    var folder: String { (path as NSString).deletingLastPathComponent }

    var ownedIDs: [String] { [bundleID] + nestedBundleIDs }

    var matchNames: [String] {
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var seen = Set<String>()
        return [name, executable, fileName].compactMap { $0 }.filter { candidate in
            candidate.count >= 3 && seen.insert(candidate.lowercased()).inserted
        }
    }
}

nonisolated enum LibraryDomain: String, Codable, Sendable {
    case user, system
}

nonisolated enum LeftoverKind: String, Sendable {
    case settings, cache, log, windowState, service, data
}

nonisolated enum MatchKind: String, Sendable {
    case bundleID, teamID, name
}

nonisolated enum LibraryFolder: String, CaseIterable, Codable, Sendable {
    case preferences = "Preferences"
    case preferencesByHost = "Preferences/ByHost"
    case caches = "Caches"
    case applicationSupport = "Application Support"
    case applicationScripts = "Application Scripts"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case savedState = "Saved Application State"
    case logs = "Logs"
    case httpStorages = "HTTPStorages"
    case webKit = "WebKit"
    case cookies = "Cookies"
    case launchAgents = "LaunchAgents"
    case launchDaemons = "LaunchDaemons"
    case privilegedHelperTools = "PrivilegedHelperTools"

    static func folders(in domain: LibraryDomain) -> [LibraryFolder] {
        switch domain {
        case .user:
            [.preferences, .preferencesByHost, .caches, .applicationSupport, .applicationScripts, .containers,
             .groupContainers, .savedState, .logs, .httpStorages, .webKit, .cookies, .launchAgents]
        case .system:
            [.launchDaemons, .launchAgents, .privilegedHelperTools, .applicationSupport, .preferences, .caches, .logs]
        }
    }

    var isProtected: Bool { self == .containers || self == .groupContainers }

    var allowsNameMatch: Bool { self == .applicationSupport || self == .caches || self == .logs }

    var kind: LeftoverKind {
        switch self {
        case .preferences, .preferencesByHost: .settings
        case .caches, .httpStorages, .webKit: .cache
        case .logs: .log
        case .savedState: .windowState
        case .launchAgents, .launchDaemons: .service
        default: .data
        }
    }
}

nonisolated struct LibraryEntry: Hashable, Sendable {
    var url: URL
    var domain: LibraryDomain
    var folder: LibraryFolder

    var name: String { url.lastPathComponent }
}

nonisolated struct LeftoverItem: Hashable, Sendable, Identifiable {
    var entry: LibraryEntry
    var match: MatchKind
    var size: Int64?
    var isAccessible: Bool

    var id: URL { entry.url }
    var kind: LeftoverKind { entry.folder.kind }
    var needsAdmin: Bool { entry.domain == .system }
    var isSelectedByDefault: Bool { match != .name && isAccessible }

    static func make(_ entry: LibraryEntry, match: MatchKind, canReadProtected: Bool) -> LeftoverItem {
        let blocked = entry.domain == .user && entry.folder.isProtected && !canReadProtected
        return LeftoverItem(entry: entry, match: match, size: nil, isAccessible: !blocked)
    }
}
