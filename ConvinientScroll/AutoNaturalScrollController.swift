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

    func start(devicePresence: DevicePresenceMonitor, naturalScroll: NaturalScrollSettingMonitor) {
        // Idempotent start.
        guard cancellables.isEmpty else { return }
        self.naturalScroll = naturalScroll

        devicePresence.$hasMouse
            .combineLatest(devicePresence.$hasTrackpad)
            .map { hasMouse, hasTrackpad -> Bool? in
                // Only act when we have a positive signal for trackpad or mouse.
                // If nothing is detected, do nothing (avoid fighting with unknown state).
                if !hasMouse && !hasTrackpad { return nil }
                return hasTrackpad && !hasMouse
            }
            .removeDuplicates { lhs, rhs in lhs == rhs }
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] target in
                guard let self, let target else { return }
                self.pendingTarget = target
                self.retriesLeft = Self.maxRetries
                self.valueAtFailure = nil
                self.apply(source: .auto)
            }
            .store(in: &cancellables)

        // A failed write is retried a few times; otherwise `removeDuplicates` above
        // would leave the wrong value until the next device change.
        Timer.publish(every: Self.retryInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.retryIfNeeded() }
            .store(in: &cancellables)
    }

    private func apply(source: NaturalScrollSettingMonitor.ChangeSource) {
        guard let target = pendingTarget, let naturalScroll else { return }
        guard naturalScroll.canWriteSystemPreference else {
            // Writing is impossible (App Sandbox), retrying cannot help.
            pendingTarget = nil
            return
        }
        if naturalScroll.isNaturalScrollEnabled == target || naturalScroll.setEnabled(target, source: source) {
            pendingTarget = nil
        } else {
            valueAtFailure = naturalScroll.isNaturalScrollEnabled
        }
    }

    private func retryIfNeeded() {
        guard pendingTarget != nil, let naturalScroll else { return }
        guard retriesLeft > 0, naturalScroll.isNaturalScrollEnabled == valueAtFailure else {
            pendingTarget = nil
            return
        }
        retriesLeft -= 1
        apply(source: .autoRetry)
    }
}
