import SwiftUI
import Charts

struct ForecastChartView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        VStack(alignment: .leading, spacing: 16) {
            if totalForecastCards == 0 {
                ContentUnavailableView("No cards scheduled", systemImage: "calendar.badge.checkmark", description: Text("There are no cards scheduled in the next 30 days for this selection."))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    StatsMetricTile(title: "Cards scheduled", value: totalForecastCards.formatted(), symbol: "calendar")
                    StatsMetricTile(title: "Daily average", value: dailyAverage.formatted(.number.precision(.fractionLength(1))), symbol: "chart.bar")
                }
                if let peakDay {
                    Label {
                        Text("Busiest day: \(peakDay.date.formatted(.dateTime.month(.abbreviated).day())) · \(peakDay.dueCount) cards")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Chart {
                    ForEach(data, id: \.date) { item in
                        BarMark(x: .value("Date", item.date, unit: .day), y: .value("Cards due", item.dueCount))
                            .foregroundStyle(AppTheme.accent.gradient)
                            .cornerRadius(3)
                            .accessibilityLabel(Text(item.date, format: .dateTime.month().day()))
                            .accessibilityValue(Text("\(item.dueCount) cards scheduled"))
                    }
                    RuleMark(y: .value("Daily average", dailyAverage))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .accessibilityHidden(true)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 190)
                .accessibilityLabel("Cards scheduled over the next 30 days")
                Text("Dashed line: daily average. Counts show currently scheduled cards, not a daily review limit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
    }
}
