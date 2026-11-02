import Foundation
import OSLog

/// Diagnostics for failures that would otherwise be swallowed. Read with:
/// `log show --last 1h --predicate 'subsystem == "com.alehbarushka.convinientscroll"'`
nonisolated enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.alehbarushka.convinientscroll"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
    static let devices = Logger(subsystem: subsystem, category: "devices")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")

    /// A quarantined app launched from outside /Applications runs from a temporary
    /// read-only copy; if macOS unmounts it the process dies with SIGBUS.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    static func logLaunchEnvironment() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let path = Bundle.main.bundlePath
        general.notice("Launch: version \(version, privacy: .public) (\(build, privacy: .public)), macOS \(os, privacy: .public), bundle \(path, privacy: .public)")
        if isTranslocated {
            general.error("Running from an App Translocation copy; the app can crash if macOS unmounts it. Move it to /Applications and clear quarantine.")
        }
    }
}
