import Foundation

nonisolated struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]
    private let original: String

    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in
            part.allSatisfy({ $0.isASCII && $0.isNumber }) ? Int(part) : nil
        }
        guard !parts.isEmpty, numbers.count == parts.count else { return nil }
        components = numbers
        original = string
    }

    static var current: AppVersion? {
        let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return string.flatMap(AppVersion.init)
    }

    var description: String { original }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: max(lhs.components.count, rhs.components.count))
            == rhs.padded(to: max(lhs.components.count, rhs.components.count))
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let length = max(lhs.components.count, rhs.components.count)
        return lhs.padded(to: length).lexicographicallyPrecedes(rhs.padded(to: length))
    }

    private func padded(to length: Int) -> [Int] {
        components + Array(repeating: 0, count: length - components.count)
    }
}
