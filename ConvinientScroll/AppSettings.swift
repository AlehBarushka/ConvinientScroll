import Foundation
import Combine

/// User choices that belong to the app itself (system settings it changes live elsewhere).
@MainActor
final class AppSettings: ObservableObject {
    enum Key {
        static let autoScrollEnabled = "modules.autoScroll.enabled"
        static let shelfEnabled = "modules.shelf.enabled"
        static let shelfRetention = "shelf.retention"
    }

    /// How long a file stays on the shelf, counted from the moment it was added.
    enum ShelfRetention: String, CaseIterable, Identifiable {
        #if DEBUG
        case oneMinute
        #endif
        case oneHour
        case oneDay
        case oneWeek

        var id: String { rawValue }

        var interval: TimeInterval {
            switch self {
            #if DEBUG
            case .oneMinute: 60
            #endif
            case .oneHour: 60 * 60
            case .oneDay: 24 * 60 * 60
            case .oneWeek: 7 * 24 * 60 * 60
            }
        }

        var title: String {
            switch self {
            #if DEBUG
            case .oneMinute: "1 minute (debug)"
            #endif
            case .oneHour: "1 hour"
            case .oneDay: "24 hours"
            case .oneWeek: "7 days"
            }
        }
    }

    @Published var autoScrollEnabled: Bool {
        didSet { defaults.set(autoScrollEnabled, forKey: Key.autoScrollEnabled) }
    }

    @Published var shelfEnabled: Bool {
        didSet { defaults.set(shelfEnabled, forKey: Key.shelfEnabled) }
    }

    @Published var shelfRetention: ShelfRetention {
        didSet { defaults.set(shelfRetention.rawValue, forKey: Key.shelfRetention) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.autoScrollEnabled: true,
            Key.shelfEnabled: true,
            Key.shelfRetention: ShelfRetention.oneDay.rawValue
        ])
        autoScrollEnabled = defaults.bool(forKey: Key.autoScrollEnabled)
        shelfEnabled = defaults.bool(forKey: Key.shelfEnabled)
        shelfRetention = defaults.string(forKey: Key.shelfRetention)
            .flatMap(ShelfRetention.init(rawValue:)) ?? .oneDay
    }
}
