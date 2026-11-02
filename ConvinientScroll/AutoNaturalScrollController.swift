import Foundation
import Combine

@MainActor
final class AutoNaturalScrollController {
    private static let retryInterval: TimeInterval = 5
    private static let maxRetries = 3

    private var cancellables = Set<AnyCancellable>()
    private weak var naturalScroll: NaturalScrollSettingMonitor?

    /// Target whose write has not been confirmed yet.
    private var pendingTarget: Bool?
    private var retriesLeft = 0
    /// System value right after the last failed write. If it changes, someone else
    /// (the user) set it and a retry would override their choice.
    private var valueAtFailure: Bool?

    /// Armed only after a failed write, so an idle app has no timer running.
    private var retryTimer: Timer?

    func start(devicePresence: DevicePresenceMonitor, naturalScroll: NaturalScrollSettingMonitor, settings: AppSettings) {
        // Idempotent start.
        guard cancellables.isEmpty else { return }
        self.naturalScroll = naturalScroll

        devicePresence.$hasMouse
            .combineLatest(devicePresence.$hasTrackpad, settings.$autoScrollEnabled)
            .map { hasMouse, hasTrackpad, isEnabled -> Bool? in
                // The module is off: leave the setting to the user.
                guard isEnabled else { return nil }
                // Only act when we have a positive signal for trackpad or mouse.
                // If nothing is detected, do nothing (avoid fighting with unknown state).
                if !hasMouse && !hasTrackpad { return nil }
                return hasTrackpad && !hasMouse
            }
            .removeDuplicates { lhs, rhs in lhs == rhs }
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] target in
                guard let self else { return }
                self.cancelRetry()
                guard let target else {
                    self.pendingTarget = nil
                    return
                }
                self.pendingTarget = target
                self.retriesLeft = Self.maxRetries
                self.valueAtFailure = nil
                self.apply(source: .auto)
            }
            .store(in: &cancellables)
    }

    private func apply(source: NaturalScrollSettingMonitor.ChangeSource) {
        guard let target = pendingTarget, let naturalScroll else { return }
        // The cached value is only refreshed by notifications; read the real one before
        // deciding that nothing needs to be written.
        naturalScroll.refresh()
        guard naturalScroll.canWriteSystemPreference else {
            // Writing is impossible (App Sandbox), retrying cannot help.
            pendingTarget = nil
            return
        }
        if naturalScroll.isNaturalScrollEnabled == target || naturalScroll.setEnabled(target, source: source) {
            pendingTarget = nil
        } else {
            valueAtFailure = naturalScroll.isNaturalScrollEnabled
            // A failed write is retried a few times; otherwise `removeDuplicates` above
            // would leave the wrong value until the next device change.
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        // Added to the main run loop below, so the block runs on the main actor.
        let timer = Timer(timeInterval: Self.retryInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryIfNeeded() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func cancelRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func retryIfNeeded() {
        retryTimer = nil
        guard pendingTarget != nil, let naturalScroll else { return }
        naturalScroll.refresh()
        guard retriesLeft > 0, naturalScroll.isNaturalScrollEnabled == valueAtFailure else {
            pendingTarget = nil
            return
        }
        retriesLeft -= 1
        apply(source: .autoRetry)
    }
}
