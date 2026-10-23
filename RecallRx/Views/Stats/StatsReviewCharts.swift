import SwiftUI
import Charts

struct StatsReviewCharts: View {
    let viewModel: StatsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review history")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("\(viewModel.periodFilteredLogs.count.formatted()) reviews · \(viewModel.selectedPeriod.rawValue)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.periodFilteredLogs.isEmpty {
                ContentUnavailableView("No reviews in this period", systemImage: "chart.bar", description: Text("Try another deck or history period, or complete a study session."))
            } else {
                Chart(viewModel.reviewsPerDay, id: \.date) { item in
                    BarMark(x: .value("Date", item.date, unit: .day), y: .value("Reviews", item.count))
                        .foregroundStyle(AppTheme.accent.gradient)
                        .cornerRadius(3)
                        .accessibilityLabel(Text(item.date, format: .dateTime.month().day()))
                        .accessibilityValue(Text("\(item.count) reviews"))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 190)
                .accessibilityLabel("Daily reviews")
                if viewModel.selectedPeriod == .allTime {
                    Text("The daily chart covers the latest month. The review total includes all history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text("When you study")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Reviews by hour, in your local time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Chart(viewModel.hourlyBreakdown, id: \.hour) { item in
                    BarMark(x: .value("Hour", item.hour), y: .value("Reviews", item.count))
                        .foregroundStyle(AppTheme.accent.gradient)
                        .cornerRadius(2)
                        .accessibilityLabel(Text("Hour \(item.hour)"))
                        .accessibilityValue(Text("\(item.count) reviews"))
                }
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 160)
                .accessibilityLabel("Reviews by hour")
            }
        }
        .padding()
        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
    }
}
