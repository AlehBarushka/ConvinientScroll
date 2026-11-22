import Combine
import Foundation
import Testing
@testable import MacToolkit

@MainActor private final class ManualScheduler {
    final class Check {
        let delay: TimeInterval
        let action: () -> Void
        var cancelled = false
        init(delay: TimeInterval, action: @escaping () -> Void) {
            self.delay = delay
            self.action = action
        }
    }

    private(set) var checks: [Check] = []

    var schedule: RemovalTracker.Schedule {
        { delay, action in
            let check = Check(delay: delay, action: action)
            self.checks.append(check)
            return AnyCancellable { check.cancelled = true }
        }
    }
}

@MainActor private final class Reported {
    var apps: [InstalledApp] = []
}

private func app(_ path: String, id: String = "com.example.chatter", version: String = "1.0") -> InstalledApp {
    InstalledApp(
        path: path, bundleID: id, name: "Chatter", executable: "Chatter", version: version,
        teamID: "ABCDE12345", nestedBundleIDs: [], infoPlistModified: Date(timeIntervalSince1970: 0)
    )
}

@MainActor @Suite("RemovalTracker") struct RemovalTrackerTests {
    private let chatter = app("/Applications/Chatter.app")
    private let editor = app("/Applications/Editor.app", id: "com.example.editor")

    private func make(known: [InstalledApp]) -> (RemovalTracker, ManualScheduler, Reported) {
        let scheduler = ManualScheduler()
        let reported = Reported()
        let tracker = RemovalTracker(known: known, schedule: scheduler.schedule) { reported.apps.append($0) }
        return (tracker, scheduler, reported)
    }

    @Test func removalIsReportedAfterTheDelay() {
        let (tracker, scheduler, reported) = make(known: [chatter])
        tracker.update(current: [])
        #expect(scheduler.checks.count == 1)
        #expect(scheduler.checks[0].delay == 30)
        #expect(reported.apps.isEmpty)
        scheduler.checks[0].action()
        #expect(reported.apps == [chatter])
    }

    @Test func updateThatComesBackIsSilent() {
        let (tracker, scheduler, reported) = make(known: [chatter])
        tracker.update(current: [])
        tracker.update(current: [app("/Applications/Chatter.app", version: "2.0")])
        #expect(scheduler.checks[0].cancelled)
        scheduler.checks[0].action()
        #expect(reported.apps.isEmpty)
    }

    @Test func movedAppIsSilent() {
        let (tracker, scheduler, reported) = make(known: [chatter])
        tracker.update(current: [app("/Applications/Utilities/Chatter.app")])
        scheduler.checks.forEach { $0.action() }
        #expect(reported.apps.isEmpty)
    }

    @Test func renamedAppIsSilent() {
        let (tracker, scheduler, reported) = make(known: [chatter])
        tracker.update(current: [app("/Applications/Chatter 2.app")])
        scheduler.checks.forEach { $0.action() }
        #expect(reported.apps.isEmpty)
    }

    @Test func repeatedEventsScheduleOnce() {
        let (tracker, scheduler, _) = make(known: [chatter])
        tracker.update(current: [])
        tracker.update(current: [])
        #expect(scheduler.checks.count == 1)
    }

    @Test func unrelatedUpdateAfterRemovalAddsNoChecks() {
        let (tracker, scheduler, _) = make(known: [chatter, editor])
        tracker.update(current: [editor])
        tracker.update(current: [editor])
        #expect(scheduler.checks.count == 1)
    }

    @Test func pathThatReturnsAndDisappearsAgainGetsAFreshCheck() {
        let (tracker, scheduler, reported) = make(known: [chatter])
        tracker.update(current: [])
        tracker.update(current: [chatter])
        tracker.update(current: [])
        #expect(scheduler.checks.count == 2)
        #expect(scheduler.checks[0].cancelled)
        #expect(!scheduler.checks[1].cancelled)
        scheduler.checks[1].action()
        #expect(reported.apps == [chatter])
    }

    @Test func removedWhileOffIsReported() {
        let (tracker, scheduler, reported) = make(known: [chatter, editor])
        tracker.update(current: [editor])
        scheduler.checks.forEach { $0.action() }
        #expect(reported.apps == [chatter])
    }

    @Test func cancelAllDropsPendingChecks() {
        let (tracker, scheduler, reported) = make(known: [chatter])
        tracker.update(current: [])
        tracker.cancelAll()
        #expect(scheduler.checks[0].cancelled)
        #expect(tracker.pendingApps.isEmpty)
    }

    @Test func pendingAppsListCandidatesUntilTheirCheckRuns() {
        let (tracker, scheduler, _) = make(known: [chatter, editor])
        tracker.update(current: [])
        #expect(tracker.pendingApps == [chatter, editor])
        tracker.update(current: [editor])
        #expect(tracker.pendingApps == [chatter])
        scheduler.checks[0].action()
        #expect(tracker.pendingApps.isEmpty)
    }
}
