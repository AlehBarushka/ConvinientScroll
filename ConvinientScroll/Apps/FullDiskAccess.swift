import Foundation

nonisolated enum FullDiskAccess {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func isGranted() -> Bool {
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
