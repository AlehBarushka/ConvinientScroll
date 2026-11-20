import Foundation
import os

nonisolated enum UpdateLaunchOutcome: Equatable {
    case none
    case succeeded(String)
    case failed(version: String, reason: String)
}

nonisolated enum UpdateLaunchReport {
    static func outcome(pending: PendingUpdate?, current: AppVersion, failureReason: String?) -> UpdateLaunchOutcome {
        guard let pending else { return .none }
        if let failureReason {
            return .failed(version: pending.version, reason: failureReason)
        }
        if let target = AppVersion(pending.version), target == current {
            return .succeeded(pending.version)
        }
        return .failed(version: pending.version, reason: "The update didn't finish.")
    }

    @MainActor
    static func run(
        store: PendingUpdateStore,
        failureFile: URL,
        current: AppVersion,
        isLoginItemEnabled: () -> Bool,
        enableLoginItem: () -> Void,
        showAlert: (_ title: String, _ text: String) -> Void
    ) {
        let pending = store.load()
        let reason = readReason(at: failureFile)
        let result = outcome(pending: pending, current: current, failureReason: reason)

        if let pending, pending.reregisterLoginItem, !isLoginItemEnabled() {
            enableLoginItem()
        }

        switch result {
        case .none:
            break
        case .succeeded(let version):
            AppLog.updates.notice("Updated to \(version, privacy: .public)")
        case .failed(let version, let reason):
            AppLog.updates.error("Update to \(version, privacy: .public) failed: \(reason, privacy: .public)")
            showAlert(
                "Couldn't install Mac Toolkit \(version)",
                "\(reason) Mac Toolkit \(current) is still installed."
            )
        }

        store.clear()
        removeFile(at: failureFile)
    }

    private static func readReason(at url: URL) -> String? {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            AppLog.updates.error("Couldn't read the update failure file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func removeFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            AppLog.updates.error("Couldn't delete the update failure file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
