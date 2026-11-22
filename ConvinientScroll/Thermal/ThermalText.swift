import Foundation

nonisolated enum ThermalText {
    static func menuBar(celsius: Int?) -> String {
        celsius.map { "\($0)°" } ?? "—°"
    }

    static func detail(celsius: Int?, fanPercent: Int?, level: ThermalLevel?) -> String {
        var parts = ["CPU \(menuBar(celsius: celsius))"]
        if let fanPercent { parts.append("Fan \(fanPercent)%") }
        parts.append(level?.title ?? "—")
        return parts.joined(separator: " · ")
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
