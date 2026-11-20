import Foundation
import Testing
@testable import MacToolkit

@MainActor @Suite("UpdateLaunchReport") struct UpdateLaunchReportTests {
    private let older = AppVersion("2.3.1")!
    private let target = AppVersion("2.4.0")!

    private final class Probe {
        var enableCalls = 0
        var alerts: [(String, String)] = []
    }

    private func withSandbox(_ body: (PendingUpdateStore, URL) throws -> Void) rethrows {
        let suite = "UpdateLaunchReportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "failure-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try body(PendingUpdateStore(defaults: defaults), file)
    }

    private func run(
        _ store: PendingUpdateStore, _ file: URL, current: AppVersion,
        loginItemEnabled: Bool, probe: Probe
    ) {
        UpdateLaunchReport.run(
            store: store, failureFile: file, current: current,
            isLoginItemEnabled: { loginItemEnabled },
            enableLoginItem: { probe.enableCalls += 1 },
            showAlert: { probe.alerts.append(($0, $1)) }
        )
    }

    @Test func noPendingIsNone() {
        #expect(UpdateLaunchReport.outcome(pending: nil, current: older, failureReason: nil) == .none)
        #expect(UpdateLaunchReport.outcome(pending: nil, current: older, failureReason: "X") == .none)
    }

    @Test func reasonMeansFailed() {
        let pending = PendingUpdate(version: "2.4.0", reregisterLoginItem: false)
        #expect(UpdateLaunchReport.outcome(pending: pending, current: older, failureReason: "X")
            == .failed(version: "2.4.0", reason: "X"))
    }

    @Test func matchingVersionSucceeded() {
        let pending = PendingUpdate(version: "2.4.0", reregisterLoginItem: false)
        #expect(UpdateLaunchReport.outcome(pending: pending, current: target, failureReason: nil) == .succeeded("2.4.0"))
    }

    @Test func otherVersionWithoutReasonFailed() {
        let pending = PendingUpdate(version: "2.4.0", reregisterLoginItem: false)
        #expect(UpdateLaunchReport.outcome(pending: pending, current: older, failureReason: nil)
            == .failed(version: "2.4.0", reason: "The update didn't finish."))
    }

    @Test func unparsableVersionWithoutReasonFailed() {
        let pending = PendingUpdate(version: "beta", reregisterLoginItem: false)
        #expect(UpdateLaunchReport.outcome(pending: pending, current: older, failureReason: nil)
            == .failed(version: "beta", reason: "The update didn't finish."))
    }

    @Test func reregistersLoginItemWhenRequested() {
        withSandbox { store, file in
            store.save(PendingUpdate(version: "2.4.0", reregisterLoginItem: true))
            let probe = Probe()
            run(store, file, current: target, loginItemEnabled: false, probe: probe)
            #expect(probe.enableCalls == 1)
            #expect(probe.alerts.isEmpty)
            #expect(store.load() == nil)
        }
    }

    @Test func doesNotReregisterWhenAlreadyEnabledOrNotRequested() {
        withSandbox { store, file in
            let probe = Probe()
            store.save(PendingUpdate(version: "2.4.0", reregisterLoginItem: true))
            run(store, file, current: target, loginItemEnabled: true, probe: probe)
            store.save(PendingUpdate(version: "2.4.0", reregisterLoginItem: false))
            run(store, file, current: target, loginItemEnabled: false, probe: probe)
            #expect(probe.enableCalls == 0)
        }
    }

    @Test func rollbackStillReregistersLoginItem() throws {
        try withSandbox { store, file in
            store.save(PendingUpdate(version: "2.4.0", reregisterLoginItem: true))
            try "Rolled back.\n".write(to: file, atomically: true, encoding: .utf8)
            let probe = Probe()
            run(store, file, current: older, loginItemEnabled: false, probe: probe)
            #expect(probe.enableCalls == 1)
            #expect(probe.alerts.count == 1)
        }
    }

    @Test func failedRunShowsAlertAndCleansUp() throws {
        try withSandbox { store, file in
            store.save(PendingUpdate(version: "2.4.0", reregisterLoginItem: false))
            try "The app didn't quit in time.\n".write(to: file, atomically: true, encoding: .utf8)
            let probe = Probe()
            run(store, file, current: older, loginItemEnabled: true, probe: probe)
            #expect(probe.alerts.count == 1)
            #expect(probe.alerts.first?.0 == "Couldn't install Mac Toolkit 2.4.0")
            #expect(probe.alerts.first?.1 == "The app didn't quit in time. Mac Toolkit 2.3.1 is still installed.")
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(store.load() == nil)
        }
    }

    @Test func staleFailureFileIsDeletedWithoutPending() throws {
        try withSandbox { store, file in
            try "Old.\n".write(to: file, atomically: true, encoding: .utf8)
            let probe = Probe()
            run(store, file, current: older, loginItemEnabled: true, probe: probe)
            #expect(probe.alerts.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }
}
