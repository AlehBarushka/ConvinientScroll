import Foundation
import Combine

final class UpdateModel: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(AppVersion)
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, Double)
        case installing(AvailableUpdate)
        case failed(UpdateError, page: URL?)
    }

    typealias Check = () async throws(UpdateError) -> UpdateCheckResult
    typealias Install = (AvailableUpdate, @escaping @Sendable (Double) -> Void) async throws(UpdateError) -> Void

    let current: AppVersion
    @Published private(set) var state: State = .idle

    private let check: Check
    private let install: Install
    private let openURL: (URL) -> Void
    private var task: Task<Void, Never>?
    private var generation = 0

    init(current: AppVersion, check: @escaping Check, install: @escaping Install, openURL: @escaping (URL) -> Void) {
        self.current = current
        self.check = check
        self.install = install
        self.openURL = openURL
    }

    func checkForUpdates() {
        switch state {
        case .idle, .upToDate, .failed: break
        default: return
        }
        let id = beginTask()
        state = .checking
        task = Task { [check] in
            let result: Result<UpdateCheckResult, UpdateError>
            do throws(UpdateError) {
                result = .success(try await check())
            } catch {
                result = .failure(error)
            }
            guard isCurrent(id) else { return }
            switch result {
            case .success(.upToDate(let version)): state = .upToDate(version)
            case .success(.available(let update)): state = .available(update)
            case .failure(let error): state = .failed(error, page: nil)
            }
        }
    }

    func installUpdate() {
        guard case .available(let update) = state else { return }
        let id = beginTask()
        state = .downloading(update, 0)
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            let model = self
            Task { @MainActor in model?.receiveProgress(fraction, of: update, id: id) }
        }
        task = Task { [install] in
            do throws(UpdateError) {
                try await install(update, report)
            } catch {
                guard isCurrent(id) else { return }
                state = .failed(error, page: update.pageURL)
            }
        }
    }

    func viewOnGitHub() {
        switch state {
        case .available(let update): openURL(update.pageURL)
        case .failed(_, let page?): openURL(page)
        default: break
        }
    }

    func dismiss() {
        beginTask()
        state = .idle
    }

    @discardableResult
    private func beginTask() -> Int {
        task?.cancel()
        task = nil
        generation += 1
        return generation
    }

    private func isCurrent(_ id: Int) -> Bool {
        id == generation && !Task.isCancelled
    }

    private func receiveProgress(_ fraction: Double, of update: AvailableUpdate, id: Int) {
        guard id == generation else { return }
        switch state {
        case .available, .downloading:
            state = fraction >= 1 ? .installing(update) : .downloading(update, fraction)
        default:
            break
        }
    }
}
