import Foundation
import OSLog
import Combine
import Darwin
import Security

@MainActor
final class NaturalScrollSettingMonitor: ObservableObject {
    enum ChangeSource {
        case user
        case auto
        /// Repeat of a failed `.auto` write; its failure is not announced again.
        case autoRetry
    }

    @Published private(set) var isNaturalScrollEnabled: Bool = false
    /// False only when writing is impossible (App Sandbox). A failed write does not
    /// clear it, so the user and the auto controller can try again.
    @Published private(set) var canWriteSystemPreference: Bool = true
    @Published private(set) var writeBlockedReason: String?

    /// Last failed write; kept until a write succeeds so the periodic
    /// `updateWriteCapability()` does not wipe the message.
    private var writeFailureReason: String?

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

    /// Returns whether the system value equals `enabled` after the call.
    @discardableResult
    func setEnabled(_ enabled: Bool, source: ChangeSource = .user) -> Bool {
        updateWriteCapability()
        guard canWriteSystemPreference else { return false }
        let sandboxed = isSandboxed()

        // Avoid unnecessary writes (helps prevent oscillation with the auto controller).
        if readEffectiveValue() == enabled {
            writeFailureReason = nil
            updateWriteCapability()
            refresh()
            return true
        }

        // Match System Settings: write only to the global domain (-g).
        writeGlobalPreference(enabled)
        clearCurrentHostOverrideBestEffort()

        // Verify read-after-write. In App Sandbox the call above can fail and only
        // emit a console warning, leaving UI “enabled” but ineffective.
        var didStick = (readEffectiveValue() == enabled)
        if !didStick, !sandboxed {
            // Fallback: explicitly call `defaults write -g ...`.
            AppLog.preferences.notice("CFPreferences write did not stick (enabled=\(enabled)); falling back to `defaults write`")
            _ = writeUsingDefaultsCommand(enabled)
            clearCurrentHostOverrideBestEffort()
            didStick = (readEffectiveValue() == enabled)
        }

        if didStick {
            writeFailureReason = nil
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
            return true
        } else {
            // Force UI back to actual system state and show a helpful message.
            refresh()
            let reason: String
            if sandboxed {
                reason = "macOS blocked changing this system setting because the app is running in App Sandbox. Build/distribute a non-sandboxed version."
            } else {
                reason = "Couldn’t change the system Natural Scroll setting. The write did not persist (CFPreferences/defaults). Try restarting the app or logging out/in."
            }
            writeFailureReason = reason
            writeBlockedReason = reason
            AppLog.preferences.error("Failed to set Natural Scroll to \(enabled) (source=\(String(describing: source)), sandboxed=\(sandboxed))")
            if source != .autoRetry {
                NotificationService.shared.showNaturalScrollChanged(enabled: enabled, applied: false)
            }
            return false
        }
    }

    private func updateWriteCapability() {
        let sandboxed = isSandboxed()
        if sandboxed {
            canWriteSystemPreference = false
            writeBlockedReason = "The app is running in App Sandbox, so it cannot change the system Natural Scroll setting."
        } else {
            canWriteSystemPreference = true
            writeBlockedReason = writeFailureReason
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
        if !CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) {
            AppLog.preferences.error("CFPreferencesSynchronize returned false after writing the global preference")
        }
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

    private typealias SwipeScrollDirectionFn = @convention(c) (Bool) -> Void

    /// Resolved once on first use. The handle is kept open on purpose: the framework
    /// lives in the dyld shared cache, so `dlclose` would unload nothing anyway.
    private static let swipeScrollDirectionFunction: SwipeScrollDirectionFn? = {
        // PreferencePanesSupport.framework exports a function used by the
        // Mouse/Trackpad preference panes to apply this instantly.
        // We load it dynamically to avoid hard-linking private frameworks.
        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            AppLog.preferences.error("Cannot load PreferencePanesSupport: \(reason, privacy: .public)")
            return nil
        }

        for symbol in ["setSwipeScrollDirection", "_setSwipeScrollDirection"] {
            if let sym = dlsym(handle, symbol) {
                AppLog.preferences.info("Resolved private symbol \(symbol, privacy: .public)")
                return unsafeBitCast(sym, to: SwipeScrollDirectionFn.self)
            }
        }
        AppLog.preferences.error("PreferencePanesSupport has no known swipe-scroll symbol; scroll direction will update only after re-login")
        return nil
    }()

    private func applySwipeScrollDirectionBestEffort(_ enabled: Bool) {
        Self.swipeScrollDirectionFunction?(enabled)
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
        Self.runProcess(path, args)
    }

    /// Runs on the main thread, so a hung child (e.g. `defaults` waiting on a stuck
    /// cfprefsd) must not be waited for forever.
    private nonisolated static let processTimeout: TimeInterval = 5

    private nonisolated static func runProcess(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args

        let finished = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in finished.signal() }

        do {
            try p.run()
        } catch {
            AppLog.preferences.error("Cannot launch \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }

        if finished.wait(timeout: .now() + processTimeout) == .timedOut {
            p.terminate()
            AppLog.preferences.error("\(path, privacy: .public) \(args.joined(separator: " "), privacy: .public) timed out after \(processTimeout, format: .fixed(precision: 0))s and was terminated")
            return false
        }

        // `defaults delete` of a missing key exits non-zero in normal operation.
        if p.terminationStatus != 0 {
            AppLog.preferences.debug("\(path, privacy: .public) \(args.joined(separator: " "), privacy: .public) exited with status \(p.terminationStatus)")
        }
        return p.terminationStatus == 0
    }
}

