import Foundation

nonisolated enum ThrottleAlert: Equatable {
    case heavy, critical
}

nonisolated struct ThrottleAlertPolicy {
    static let heavyCooldown: TimeInterval = 600

    private var lastHeavy: Date?

    mutating func alert(from previous: ThermalLevel?, to next: ThermalLevel?, at date: Date) -> ThrottleAlert? {
        switch next {
        case .critical where previous != .critical:
            return .critical
        case .heavy where !(previous?.isThrottling ?? false):
            if let lastHeavy, date.timeIntervalSince(lastHeavy) < Self.heavyCooldown { return nil }
            lastHeavy = date
            return .heavy
        default:
            return nil
        }
    }
}
