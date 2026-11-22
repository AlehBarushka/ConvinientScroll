import Foundation
import Security

nonisolated struct AppScanner: Sendable {
    var roots: [URL]
    var maxDepth = 3
    var teamID: @Sendable (URL) -> String?

    static let nestedDepthLimit = 5
    static let nestedExtensions: Set<String> = ["app", "appex", "xpc", "systemextension"]

    static let live = AppScanner(
        roots: [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        ],
        teamID: { TeamIdentifier.read(appAt: $0) }
    )

    func appURLs() -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants, .skipsHiddenFiles]
                  )
            else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    result.append(url)
                } else if enumerator.level >= maxDepth {
                    enumerator.skipDescendants()
                }
            }
        }
        return result
    }

    func scan(reusing previous: [InstalledApp]) -> [InstalledApp] {
        let known = Dictionary(previous.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return appURLs().compactMap { url in
            if let old = known[url.path], old.infoPlistModified == Self.plistModified(of: url) {
                return old
            }
            return Self.read(appAt: url, teamID: teamID)
        }
    }

    static func read(appAt url: URL, teamID: (URL) -> String?) -> InstalledApp? {
        let plistURL = url.appending(path: "Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              let modified = plistModified(of: url)
        else { return nil }
        let fileName = url.deletingPathExtension().lastPathComponent
        return InstalledApp(
            path: url.path,
            bundleID: bundleID,
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fileName,
            executable: info["CFBundleExecutable"] as? String,
            version: (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String),
            teamID: teamID(url),
            nestedBundleIDs: nestedIDs(in: url, excluding: bundleID),
            infoPlistModified: modified
        )
    }

    private static func plistModified(of url: URL) -> Date? {
        let values = try? url.appending(path: "Contents/Info.plist").resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private static func nestedIDs(in app: URL, excluding ownID: String) -> [String] {
        let fileManager = FileManager.default
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        var ids = Set<String>()
        if let enumerator = fileManager.enumerator(
            at: contents,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if enumerator.level > nestedDepthLimit {
                    enumerator.skipDescendants()
                    continue
                }
                guard nestedExtensions.contains(url.pathExtension) else { continue }
                enumerator.skipDescendants()
                let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist")) as? [String: Any]
                if let id = info?["CFBundleIdentifier"] as? String { ids.insert(id) }
            }
        }
        let launchServices = contents.appending(path: "Library/LaunchServices", directoryHint: .isDirectory)
        let helpers = (try? fileManager.contentsOfDirectory(atPath: launchServices.path)) ?? []
        for name in helpers where !name.hasPrefix(".") { ids.insert(name) }
        ids.remove(ownID)
        return ids.sorted()
    }
}

nonisolated enum TeamIdentifier {
    static func read(appAt url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
