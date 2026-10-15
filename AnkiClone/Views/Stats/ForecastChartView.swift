import SwiftUI
import Charts

struct ForecastChartView: View {
    let data: [(date: Date, dueCount: Int)]

    private var totalForecastCards: Int {
        data.reduce(0) { $0 + $1.dueCount }
    }

    private var peakDay: (date: Date, dueCount: Int)? {
        data.max { $0.dueCount < $1.dueCount }
    }

    private var dailyAverage: Double {
        guard !data.isEmpty else { return 0 }
        return Double(totalForecastCards) / Double(data.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Metrics Summary
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Due (30d)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(totalForecastCards)")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Average")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", dailyAverage))
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 28)

                if let peak = peakDay, peak.dueCount > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Peak Day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(peak.dueCount)")
                            .font(.title3.bold())
                            .foregroundStyle(.purple)
                    }
                }

                Spacer()
            }

            if totalForecastCards == 0 {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No cards due in the next 30 days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                // Chart
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Due Cards", item.dueCount)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(3)
                    }

                    if dailyAverage > 0 {
                        RuleMark(
                            y: .value("Average", dailyAverage)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Avg: \(String(format: "%.1f", dailyAverage))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
