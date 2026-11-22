import AppKit

enum PauseReason: Hashable, CaseIterable {
    case systemSleep, displaySleep, sessionInactive
}

@MainActor
final class WorkspacePauseObserver {
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping (PauseReason, _ paused: Bool) -> Void) {
        let pairs: [(pause: Notification.Name, resume: Notification.Name, reason: PauseReason)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, .systemSleep),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, .displaySleep),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive)
        ]
        let center = NSWorkspace.shared.notificationCenter
        for pair in pairs {
            observers.append(center.addObserver(forName: pair.pause, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange(pair.reason, true) }
            })
            observers.append(center.addObserver(forName: pair.resume, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange(pair.reason, false) }
            })
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }
}
