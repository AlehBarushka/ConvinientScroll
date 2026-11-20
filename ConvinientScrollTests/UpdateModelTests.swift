import Combine
import Foundation
import Testing
@testable import MacToolkit

@MainActor @Suite("UpdateModel", .timeLimit(.minutes(1))) struct UpdateModelTests {
    private let current = AppVersion("2.3.0")!
    private let update = AvailableUpdate(
        version: AppVersion("2.4.0")!,
        pageURL: URL(string: "https://example.com/release")!,
        diskImageURL: URL(string: "https://example.com/Mac.dmg")!
    )

    private final class Probe {
        var checks = 0
        var opened: [URL] = []
        var installSawCancellation: Bool?
        var progress: (@Sendable (Double) -> Void)?
        let installFinished = AsyncStream<Void>.makeStream()
    }

    private typealias Install = (AvailableUpdate, @escaping @Sendable (Double) -> Void) async throws(UpdateError) -> Void

    private func makeModel(
        probe: Probe,
        check: @escaping () async throws(UpdateError) -> UpdateCheckResult,
        install: @escaping Install = { _, _ in }
    ) -> UpdateModel {
        UpdateModel(
            current: current,
            check: { () async throws(UpdateError) -> UpdateCheckResult in
                probe.checks += 1
                return try await check()
            },
            install: install,
            openURL: { probe.opened.append($0) }
        )
    }

    private func wait(_ model: UpdateModel, for expected: UpdateModel.State) async {
        for await state in model.$state.values where state == expected { return }
    }

    private func hangingInstall(_ probe: Probe, reporting value: Double? = nil, thenThrow error: UpdateError? = nil) -> Install {
        { _, progress in
            probe.progress = progress
            if let value { progress(value) }
            try? await Task.sleep(for: .seconds(3600))
            probe.installSawCancellation = Task.isCancelled
            probe.installFinished.continuation.yield()
            if let error { throw error }
        }
    }

    private func startDownload(_ model: UpdateModel, progress: Double) async {
        model.checkForUpdates()
        await wait(model, for: .available(update))
        model.installUpdate()
        await wait(model, for: .downloading(update, progress))
    }

    @Test func checkShowsUpToDate() async {
        let model = makeModel(probe: Probe(), check: { .upToDate(AppVersion("2.3.1")!) })
        model.checkForUpdates()
        #expect(model.state == .checking)
        await wait(model, for: .upToDate(AppVersion("2.3.1")!))
    }

    @Test func checkShowsAvailable() async {
        let u = update
        let model = makeModel(probe: Probe(), check: { .available(u) })
        model.checkForUpdates()
        await wait(model, for: .available(u))
    }

    @Test func checkErrorShowsFailedWithoutPage() async {
        let model = makeModel(probe: Probe(), check: { () throws(UpdateError) -> UpdateCheckResult in throw .network })
        model.checkForUpdates()
        await wait(model, for: .failed(.network, page: nil))
    }

    @Test func installReportsProgress() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: hangingInstall(probe, reporting: 0.5))
        await startDownload(model, progress: 0.5)
        model.dismiss()
    }

    @Test func fullProgressSwitchesToInstalling() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: hangingInstall(probe, reporting: 1.0))
        model.checkForUpdates()
        await wait(model, for: .available(u))
        model.installUpdate()
        await wait(model, for: .installing(u))
        model.dismiss()
    }

    @Test func installErrorKeepsPage() async {
        let u = update
        let model = makeModel(probe: Probe(), check: { .available(u) }, install: { _, _ throws(UpdateError) in throw .wrongDeveloper })
        model.checkForUpdates()
        await wait(model, for: .available(u))
        model.installUpdate()
        await wait(model, for: .failed(.wrongDeveloper, page: u.pageURL))
    }

    @Test func checkWhileBusyIsIgnored() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: hangingInstall(probe, reporting: 0.5))
        await startDownload(model, progress: 0.5)
        model.checkForUpdates()
        #expect(probe.checks == 1)
        #expect(model.state == .downloading(u, 0.5))
        model.dismiss()
    }

    @Test func closingWindowCancelsInstall() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: hangingInstall(probe, reporting: 0.5))
        await startDownload(model, progress: 0.5)
        model.dismiss()
        #expect(model.state == .idle)
        for await _ in probe.installFinished.stream { break }
        #expect(probe.installSawCancellation == true)
        #expect(model.state == .idle)
    }

    @Test func errorAfterDismissDoesNotChangeState() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: hangingInstall(probe, reporting: 0.5, thenThrow: .network))
        await startDownload(model, progress: 0.5)
        model.dismiss()
        for await _ in probe.installFinished.stream { break }
        for _ in 0..<5 { await Task.yield() }
        #expect(model.state == .idle)
    }

    @Test func progressAfterDismissIsIgnored() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: hangingInstall(probe, reporting: 0.5))
        await startDownload(model, progress: 0.5)
        model.dismiss()
        probe.progress?(0.9)
        for _ in 0..<5 { await Task.yield() }
        #expect(model.state == .idle)
    }

    @Test func dismissDuringCheckIgnoresItsResult() async {
        let u = update
        let gate = AsyncStream<Void>.makeStream()
        let model = makeModel(probe: Probe(), check: {
            for await _ in gate.stream { break }
            return .available(u)
        })
        model.checkForUpdates()
        model.dismiss()
        gate.continuation.yield()
        for _ in 0..<5 { await Task.yield() }
        #expect(model.state == .idle)
    }

    @Test func viewOnGitHubOpensReleasePage() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) })
        model.checkForUpdates()
        await wait(model, for: .available(u))
        model.viewOnGitHub()
        #expect(probe.opened == [u.pageURL])
    }

    @Test func viewOnGitHubFromFailureUsesPage() async {
        let u = update
        let probe = Probe()
        let model = makeModel(probe: probe, check: { .available(u) }, install: { _, _ throws(UpdateError) in throw .applicationsNotWritable })
        model.checkForUpdates()
        await wait(model, for: .available(u))
        model.installUpdate()
        await wait(model, for: .failed(.applicationsNotWritable, page: u.pageURL))
        model.viewOnGitHub()
        #expect(probe.opened == [u.pageURL])
    }
}
