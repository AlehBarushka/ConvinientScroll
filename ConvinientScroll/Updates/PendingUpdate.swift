import Foundation

nonisolated struct PendingUpdate: Codable, Equatable {
    let version: String
    let reregisterLoginItem: Bool
}

nonisolated struct PendingUpdateStore {
    static let key = "PendingUpdate"

    static let failureFileURL = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "com.alehbarushka.convinientscroll", directoryHint: .isDirectory)
        .appending(path: "Update", directoryHint: .isDirectory)
        .appending(path: "failure.txt")

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save(_ pending: PendingUpdate) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func load() -> PendingUpdate? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(PendingUpdate.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
