import Foundation
import OSLog

nonisolated struct RemovedApp: Codable, Hashable, Sendable, Identifiable {
    var app: InstalledApp
    var removedAt: Date

    var id: String { app.bundleID }
}

nonisolated struct AppsStore: Sendable {
    var root: URL

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.alehbarushka.convinientscroll"
        return base.appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "Apps", directoryHint: .isDirectory)
    }

    func loadIndex() -> [InstalledApp]? {
        read([InstalledApp].self, from: indexURL)
    }

    @discardableResult
    func saveIndex(_ apps: [InstalledApp]) -> Bool {
        write(apps, to: indexURL)
    }

    func loadRemoved() -> [RemovedApp] {
        read([RemovedApp].self, from: removedURL) ?? []
    }

    func saveRemoved(_ removed: [RemovedApp]) {
        _ = write(removed, to: removedURL)
    }

    private var indexURL: URL { root.appending(path: "index.json") }
    private var removedURL: URL { root.appending(path: "removed.json") }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            AppLog.apps.error("Cannot read \(url.lastPathComponent, privacy: .public) at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            AppLog.apps.error("Cannot write \(url.lastPathComponent, privacy: .public) at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
