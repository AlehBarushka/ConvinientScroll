nonisolated enum ThermalTint: Equatable {
    case none, warning, critical
}

nonisolated enum ThermalLevel: Int, CaseIterable, Comparable, Sendable {
    case nominal, moderate, heavy, critical

    init?(rawState: UInt64) {
        switch rawState {
        case 0: self = .nominal
        case 1: self = .moderate
        case 2: self = .heavy
        case 3, 4: self = .critical
        default: return nil
        }
    }

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .nominal: "Nominal"
        case .moderate: "Moderate"
        case .heavy: "Heavy"
        case .critical: "Critical"
        }
    }

    var isThrottling: Bool { self >= .heavy }

    var tint: ThermalTint {
        switch self {
        case .nominal, .moderate: .none
        case .heavy: .warning
        case .critical: .critical
        }
    }
}
