import Charts
import Combine
import SwiftUI

nonisolated enum ThermalChartScale {
    static func top(for points: [ThermalPoint]) -> Double {
        let hottest = points.compactMap(\.celsius).max() ?? 0
        return max(110, (hottest / 10).rounded(.up) * 10)
    }
}

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
            Text(ThermalText.statistics(model.durations))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
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
                    yEnd: .value("Top", chartTop)
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
        .chartYScale(domain: 0...chartTop)
        .chartXScale(domain: timeDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100])
        }
        .chartLegend(.hidden)
    }

    private var chartTop: Double {
        ThermalChartScale.top(for: model.points)
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

    private static func bandColor(_ level: ThermalLevel) -> Color {
        switch level {
        case .nominal: .clear
        case .moderate: .yellow.opacity(0.08)
        case .heavy: .yellow.opacity(0.25)
        case .critical: .red.opacity(0.25)
        }
    }
}
