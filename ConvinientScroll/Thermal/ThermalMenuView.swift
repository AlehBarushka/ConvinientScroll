import Charts
import Combine
import SwiftUI

final class ThermalMenuModel: ObservableObject {
    @Published var detail = ""
    @Published var points: [ThermalPoint] = []
    @Published var durations: [LevelDuration] = []
}

struct ThermalMenuView: View {
    @ObservedObject var model: ThermalMenuModel

    private struct Band: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let level: ThermalLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hasFan ? "Last 10 minutes · CPU °C · fan % dashed" : "Last 10 minutes · CPU °C")
                .font(.caption)
                .foregroundStyle(.secondary)
            chart
                .frame(height: 120)
            Text(statistics)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 300, alignment: .leading)
    }

    private var chart: some View {
        Chart {
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("Start", band.start),
                    xEnd: .value("End", band.end),
                    yStart: .value("Bottom", 0),
                    yEnd: .value("Top", 110)
                )
                .foregroundStyle(Self.bandColor(band.level))
            }
            ForEach(model.points.filter { $0.celsius != nil }) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("CPU", point.celsius ?? 0),
                    series: .value("Line", "cpu-\(point.segment)")
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(model.points.filter { $0.fanPercent != nil }) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Fan", point.fanPercent ?? 0),
                    series: .value("Line", "fan-\(point.segment)")
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...110)
        .chartXScale(domain: timeDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100])
        }
        .chartLegend(.hidden)
    }

    private var hasFan: Bool {
        model.points.contains { $0.fanPercent != nil }
    }

    private var timeDomain: ClosedRange<Date> {
        let end = model.points.last?.date ?? Date()
        return end.addingTimeInterval(-ThermalHistory.window)...end
    }

    private var bands: [Band] {
        let points = model.points
        var bands: [Band] = []
        var index = 0
        while index < points.count {
            let first = points[index]
            var last = index
            while last + 1 < points.count,
                  points[last + 1].level == first.level,
                  points[last + 1].segment == first.segment {
                last += 1
            }
            let next = last + 1 < points.count && points[last + 1].segment == first.segment ? points[last + 1] : points[last]
            if let level = first.level, level != .nominal {
                bands.append(Band(id: first.id, start: first.date, end: next.date, level: level))
            }
            index = last + 1
        }
        return bands
    }

    private var statistics: String {
        let parts = model.durations.map { "\($0.level.title) \(ThermalText.duration($0.seconds))" }
        return "Since enabled: " + (parts.isEmpty ? "—" : parts.joined(separator: " · "))
    }

    private static func bandColor(_ level: ThermalLevel) -> Color {
        switch level {
        case .nominal: .clear
        case .moderate: .yellow.opacity(0.08)
        case .heavy: .yellow.opacity(0.25)
        case .critical: .red.opacity(0.25)
        }
    }
}
