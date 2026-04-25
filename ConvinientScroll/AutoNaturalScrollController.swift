import Foundation
import Combine

@MainActor
final class AutoNaturalScrollController {
    private var cancellables = Set<AnyCancellable>()

    func start(devicePresence: DevicePresenceMonitor, naturalScroll: NaturalScrollSettingMonitor) {
        // Idempotent start.
        guard cancellables.isEmpty else { return }

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
            .sink { target in
                guard let target else { return }
                guard naturalScroll.canWriteSystemPreference else { return }
                if naturalScroll.isNaturalScrollEnabled != target {
                    naturalScroll.setEnabled(target, source: .auto)
                }
            }
            .store(in: &cancellables)
    }
}

