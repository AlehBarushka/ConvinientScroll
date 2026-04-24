import Foundation
import Combine
import Darwin

@MainActor
final class NaturalScrollSettingMonitor: ObservableObject {
    @Published private(set) var isNaturalScrollEnabled: Bool = false
    @Published private(set) var canWriteSystemPreference: Bool = true
    @Published private(set) var writeBlockedReason: String?

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        updateWriteCapability()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateWriteCapability()
                self.refresh()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        updateWriteCapability()
        guard canWriteSystemPreference else { return }

        // System-wide preference: defaults write -g com.apple.swipescrolldirection -bool <true|false>
        let global = UserDefaults(suiteName: ".GlobalPreferences")
        global?.set(enabled, forKey: "com.apple.swipescrolldirection")
        global?.synchronize()

        // Also write to standard defaults as a fallback for reads.
        UserDefaults.standard.set(enabled, forKey: "com.apple.swipescrolldirection")
        UserDefaults.standard.synchronize()

        refresh()
    }

    private func updateWriteCapability() {
        // When running inside App Sandbox, writing to .GlobalPreferences is blocked.
        let sandboxId = getenv("APP_SANDBOX_CONTAINER_ID")
        let sandboxed = (sandboxId != nil)
        if sandboxed {
            canWriteSystemPreference = false
            writeBlockedReason = "Disable App Sandbox to change the system setting."
        } else {
            canWriteSystemPreference = true
            writeBlockedReason = nil
        }
    }

    private func refresh() {
        // System-wide preference: defaults read -g com.apple.swipescrolldirection
        let global = UserDefaults(suiteName: ".GlobalPreferences")
        let value = global?.object(forKey: "com.apple.swipescrolldirection")

        // Some systems may not expose it in suite; fall back to standard.
        let boolValue: Bool
        if let n = value as? NSNumber {
            boolValue = n.boolValue
        } else if let b = value as? Bool {
            boolValue = b
        } else {
            boolValue = UserDefaults.standard.bool(forKey: "com.apple.swipescrolldirection")
        }

        if isNaturalScrollEnabled != boolValue {
            isNaturalScrollEnabled = boolValue
        }
    }
}

