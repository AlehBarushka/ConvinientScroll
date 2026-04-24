import Foundation
import Combine
import Darwin
import Security

@MainActor
final class NaturalScrollSettingMonitor: ObservableObject {
    @Published private(set) var isNaturalScrollEnabled: Bool = false
    @Published private(set) var canWriteSystemPreference: Bool = true
    @Published private(set) var writeBlockedReason: String?

    private var timer: Timer?
    private static let preferenceKey = "com.apple.swipescrolldirection" as CFString
    private static let distributedNotificationName = Notification.Name("SwipeScrollDirectionDidChangeNotification")
    private static let legacyDeviceDomainsToClear: [String] = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
        "com.apple.AppleMultitouchMouse",
        "com.apple.driver.AppleBluetoothMultitouch.mouse"
    ]

    func start() {
        guard timer == nil else { return }
        updateWriteCapability()
        // If a previous version wrote per-device overrides, remove them so that
        // System Settings remains the source of truth.
        clearDeviceOverridesBestEffort()
        // Match System Settings behavior: keep only the global value.
        clearCurrentHostOverrideBestEffort()
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
        let sandboxed = isSandboxed()

        // Match System Settings: write only to the global domain (-g).
        writeGlobalPreference(enabled)
        clearCurrentHostOverrideBestEffort()

        // Verify read-after-write. In App Sandbox the call above can fail and only
        // emit a console warning, leaving UI “enabled” but ineffective.
        var didStick = (readEffectiveValue() == enabled)
        if !didStick, !sandboxed {
            // Fallback: explicitly call `defaults write -g ...`.
            _ = writeUsingDefaultsCommand(enabled)
            clearCurrentHostOverrideBestEffort()
            didStick = (readEffectiveValue() == enabled)
        }

        if didStick {
            writeBlockedReason = nil
            // Notify other processes/UI that the setting changed.
            // Use the distributed notification so System Settings (and other observers)
            // updates immediately.
            DistributedNotificationCenter.default().postNotificationName(
                Self.distributedNotificationName,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )

            // Best-effort: apply immediately (without logout) using the same
            // private helper System Settings uses. If unavailable, we still keep
            // prefs correct; behavior may update later.
            applySwipeScrollDirectionBestEffort(enabled)

            refresh()
            NotificationService.shared.showNaturalScrollChanged(enabled: enabled, applied: true)
        } else {
            // Force UI back to actual system state and show a helpful message.
            refresh()
            canWriteSystemPreference = false
            if sandboxed {
                writeBlockedReason = "macOS blocked changing this system setting because the app is running in App Sandbox. Build/distribute a non-sandboxed version."
            } else {
                writeBlockedReason = "Couldn’t change the system Natural Scroll setting. The write did not persist (CFPreferences/defaults). Try restarting the app or logging out/in."
            }
            NotificationService.shared.showNaturalScrollChanged(enabled: enabled, applied: false)
        }
    }

    private func updateWriteCapability() {
        let sandboxed = isSandboxed()
        if sandboxed {
            canWriteSystemPreference = false
            writeBlockedReason = "The app is running in App Sandbox, so it cannot change the system Natural Scroll setting."
        } else {
            canWriteSystemPreference = true
            writeBlockedReason = nil
        }
    }

    private func refresh() {
        let boolValue = readEffectiveValue()
        if isNaturalScrollEnabled != boolValue { isNaturalScrollEnabled = boolValue }
    }

    private func readEffectiveValue() -> Bool {
        // Prefer global. We attempt to keep currentHost cleared to match System Settings.
        if let v = readValue(host: kCFPreferencesAnyHost) { return v }
        if let v = readValue(host: kCFPreferencesCurrentHost) { return v }
        return false
    }

    private func readValue(host: CFString) -> Bool? {
        let v = CFPreferencesCopyValue(
            Self.preferenceKey,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            host
        )
        if let n = v as? NSNumber { return n.boolValue }
        if let b = v as? Bool { return b }
        return nil
    }

    private func writeGlobalPreference(_ enabled: Bool) {
        // Equivalent to: defaults write -g com.apple.swipescrolldirection -bool <true|false>
        // (NSGlobalDomain / kCFPreferencesAnyApplication)
        CFPreferencesSetValue(Self.preferenceKey, enabled as CFBoolean, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func writeUsingDefaultsCommand(_ enabled: Bool) -> Bool {
        let boolArg = enabled ? "true" : "false"
        let ok1 = run("/usr/bin/defaults", ["write", "-g", "com.apple.swipescrolldirection", "-bool", boolArg])
        _ = run("/usr/bin/defaults", ["-currentHost", "delete", "-g", "com.apple.swipescrolldirection"])
        return ok1
    }

    private func clearDeviceOverridesBestEffort() {
        // Best-effort cleanup of overrides created by earlier builds.
        for d in Self.legacyDeviceDomainsToClear {
            _ = run("/usr/bin/defaults", ["delete", d, "com.apple.swipescrolldirection"])
        }
    }

    private func clearCurrentHostOverrideBestEffort() {
        // Remove any by-host override so the global value is authoritative.
        CFPreferencesSetValue(
            Self.preferenceKey,
            nil,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private func applySwipeScrollDirectionBestEffort(_ enabled: Bool) {
        // PreferencePanesSupport.framework exports a function used by the
        // Mouse/Trackpad preference panes to apply this instantly.
        // We load it dynamically to avoid hard-linking private frameworks.
        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        defer { dlclose(handle) }

        typealias Fn = @convention(c) (Bool) -> Void

        for symbol in ["setSwipeScrollDirection", "_setSwipeScrollDirection"] {
            if let sym = dlsym(handle, symbol) {
                unsafeBitCast(sym, to: Fn.self)(enabled)
                return
            }
        }
    }


    private func isSandboxed() -> Bool {
        // Reliable check: see if the process has the App Sandbox entitlement.
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = "com.apple.security.app-sandbox" as CFString
        let value = SecTaskCopyValueForEntitlement(task, entitlement, nil)
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}

