import Combine
import Foundation

@MainActor
final class RemovalTracker {
    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> AnyCancellable

    static let confirmationDelay: TimeInterval = 30

    private(set) var known: [InstalledApp]
    private var pending: [String: (app: InstalledApp, check: AnyCancellable)] = [:]
    private let schedule: Schedule
    private let onRemoved: (InstalledApp) -> Void

    init(known: [InstalledApp], schedule: @escaping Schedule, onRemoved: @escaping (InstalledApp) -> Void) {
        self.known = known
        self.schedule = schedule
        self.onRemoved = onRemoved
    }

    var pendingApps: [InstalledApp] {
        pending.values.map(\.app).sorted { $0.path < $1.path }
    }

    func update(current: [InstalledApp]) {
        let currentPaths = Set(current.map(\.path))
        for path in pending.keys.filter(currentPaths.contains) {
            pending.removeValue(forKey: path)?.check.cancel()
        }
        for app in known where !currentPaths.contains(app.path) {
            pending[app.path] = (app, schedule(Self.confirmationDelay) { [weak self] in
                self?.confirm(app)
            })
        }
        known = current
    }

    func cancelAll() {
        pending.values.forEach { $0.check.cancel() }
        pending.removeAll()
    }

    private func confirm(_ app: InstalledApp) {
        pending.removeValue(forKey: app.path)
        guard !known.contains(where: { $0.bundleID == app.bundleID }) else { return }
        onRemoved(app)
    }
}
