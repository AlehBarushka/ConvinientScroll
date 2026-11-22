import Combine
import Foundation

enum RepeatingTimer {
    typealias Schedule = (_ interval: TimeInterval, _ tolerance: TimeInterval, _ action: @escaping () -> Void) -> AnyCancellable

    static func dispatch(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping () -> Void
    ) -> AnyCancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(tolerance * 1000)))
        timer.setEventHandler { MainActor.assumeIsolated { action() } }
        timer.resume()
        return AnyCancellable { timer.cancel() }
    }
}
