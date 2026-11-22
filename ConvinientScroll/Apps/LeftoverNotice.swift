import Foundation

nonisolated enum LeftoverNotice {
    static func title(name: String, size: String) -> String {
        "\(name) left \(size) behind"
    }

    static func body(count: Int, hasService: Bool) -> String {
        let items = count == 1 ? "1 item" : "\(count) items"
        return hasService
            ? "\(items) in Library, including a background service. Click to review."
            : "\(items) in Library. Click to review."
    }
}
