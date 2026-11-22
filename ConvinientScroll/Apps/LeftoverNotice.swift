import Foundation

nonisolated enum LeftoverNotice {
    static func title(name: String, size: String) -> String {
        "\(name) left \(size) behind"
    }

    static func body(count: Int, hasService: Bool) -> String {
        let items = counted(count)
        return hasService
            ? "\(items) in Library, including a background service. Click to review."
            : "\(items) in Library. Click to review."
    }

    static func summary(_ report: RemovalReport) -> String {
        let moved = counted(report.removed.count)
        if report.adminCancelled {
            return "Moved \(moved) to the Trash. Items in /Library were left in place."
        }
        let line = "Moved \(moved) (\(ByteCountFormatter.string(fromByteCount: report.bytes, countStyle: .file))) to the Trash"
        guard !report.failed.isEmpty else { return line }
        let failed = report.failed.count == 1 ? "1 item could not be moved." : "\(report.failed.count) items could not be moved."
        return "\(line). \(failed)"
    }

    private static func counted(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}
