import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]

    @State private var viewModel: StatsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    statsContent(viewModel: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel == nil {
                    viewModel = StatsViewModel(modelContext: modelContext)
                } else {
                    viewModel?.fetchData()
                }
            }
            .refreshable {
                viewModel?.fetchData()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func statsContent(viewModel: StatsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                // Deck & Period Selectors
                topFilters(viewModel: viewModel)

                // Study Streak Banner
                studyStreakCard(viewModel: viewModel)

                // Today Summary Card
                todaySummaryCard(viewModel: viewModel)

                // Daily Reviews Chart
                dailyReviewsSection(viewModel: viewModel)

                // Card Types Donut Chart
                cardTypesDistributionSection(viewModel: viewModel)

                // Review Heatmap (Last 365 Days)
                heatmapSection(viewModel: viewModel)

                // Future Due Forecast Chart (Next 30 Days)
                forecastSection(viewModel: viewModel)

                // Hourly Breakdown Chart
                hourlyBreakdownSection(viewModel: viewModel)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Top Filters

    @ViewBuilder
    private func topFilters(viewModel: StatsViewModel) -> some View {
        VStack(spacing: 10) {
            // Deck Picker
            HStack {
                Label("Deck", systemImage: "folder.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Deck", selection: Bindable(viewModel).selectedDeck) {
                    Text("All Decks").tag(nil as Deck?)
                    ForEach(decks, id: \.id) { deck in
                        Text(deck.name).tag(Optional(deck))
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Period Selector
            Picker("Period", selection: Bindable(viewModel).selectedPeriod) {
                ForEach(StatsPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Study Streak Card

    @ViewBuilder
    private func studyStreakCard(viewModel: StatsViewModel) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: .orange.opacity(0.4), radius: 6, x: 0, y: 3)

                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.streakDays)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(viewModel.streakDays == 1 ? "day streak" : "days streak")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.streakDays > 0
                     ? "Keep up the momentum! Consistency is key to mastery."
                     : "Start reviewing today to build your study streak!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Today's Summary Card

    @ViewBuilder
    private func todaySummaryCard(viewModel: StatsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today's Study")
                    .font(.headline)
                Spacer()
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Top Metrics Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCell(
                    title: "Cards Studied",
                    value: "\(viewModel.totalReviewsToday)",
                    icon: "rectangle.stack.badge.play.fill",
                    color: .blue
                )

                metricCell(
                    title: "Time Spent",
                    value: viewModel.totalStudyTimeToday.formattedStudyTime,
                    icon: "clock.fill",
                    color: .purple
                )

                metricCell(
                    title: "Study Speed",
                    value: speedText(viewModel: viewModel),
                    icon: "bolt.fill",
                    color: .orange
                )

                metricCell(
                    title: "Retention Rate",
                    value: String(format: "%.1f%%", viewModel.retentionRate),
                    icon: "percent",
                    color: .green
                )
            }

            Divider()

            // Breakdown Pills
            HStack(spacing: 8) {
                cardBreakdownPill(
                    title: "New",
                    count: viewModel.todayNewCards,
                    color: .blue
                )

                cardBreakdownPill(
                    title: "Learning",
                    count: viewModel.todayLearningCards,
                    color: .orange
                )

                cardBreakdownPill(
                    title: "Review",
                    count: viewModel.todayReviewCards,
                    color: .green
                )
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func speedText(viewModel: StatsViewModel) -> String {
        guard viewModel.totalStudyTimeToday > 0 else { return "0.0 / min" }
        let minutes = viewModel.totalStudyTimeToday / 60.0
        let cpm = Double(viewModel.totalReviewsToday) / minutes
        return String(format: "%.1f / min", cpm)
    }

    private func metricCell(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cardBreakdownPill(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text("\(title): \(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Daily Reviews Chart

    @ViewBuilder
    private func dailyReviewsSection(viewModel: StatsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Reviews")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.periodFilteredLogs.count) reviews")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.reviewsPerDay.allSatisfy({ $0.count == 0 }) {
                emptyChartPlaceholder(message: "No reviews during this period")
            } else {
                Chart {
                    ForEach(Array(viewModel.reviewsPerDay.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Date", item.date, unit: .day),
                            y: .value("Reviews", item.count)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
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

    // MARK: - Card Types Donut Chart

    @ViewBuilder
    private func cardTypesDistributionSection(viewModel: StatsViewModel) -> some View {
        let dist = viewModel.cardStateDistribution
        let total = dist.new + dist.learning + dist.young + dist.mature

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Card Types Distribution")
                    .font(.headline)
                Spacer()
                Text("\(total) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if total == 0 {
                emptyChartPlaceholder(message: "No cards found in selection")
            } else {
                HStack(spacing: 20) {
                    // Donut Chart
                    Chart {
                        SectorMark(
                            angle: .value("Count", dist.new),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.blue)

                        SectorMark(
                            angle: .value("Count", dist.learning),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.orange)

                        SectorMark(
                            angle: .value("Count", dist.young),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.green.opacity(0.65))

                        SectorMark(
                            angle: .value("Count", dist.mature),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.green)
                    }
                    .frame(width: 130, height: 130)

                    // Legend
                    VStack(alignment: .leading, spacing: 8) {
                        typeLegendRow(title: "New", count: dist.new, total: total, color: .blue)
                        typeLegendRow(title: "Learning", count: dist.learning, total: total, color: .orange)
                        typeLegendRow(title: "Young (< 21d)", count: dist.young, total: total, color: Color.green.opacity(0.65))
                        typeLegendRow(title: "Mature (≥ 21d)", count: dist.mature, total: total, color: .green)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func typeLegendRow(title: String, count: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? (Double(count) / Double(total)) * 100.0 : 0.0
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(count)")
                .font(.caption.bold())

            Text(String(format: "(%.0f%%)", pct))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Review Heatmap

    @ViewBuilder
    private func heatmapSection(viewModel: StatsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review Heatmap (Past Year)")
                .font(.headline)

            HeatmapView(data: viewModel.heatmapData)
        }
    }

    // MARK: - Future Due Forecast

    @ViewBuilder
    private func forecastSection(viewModel: StatsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Future Due Forecast (Next 30 Days)")
                .font(.headline)

            ForecastChartView(data: viewModel.forecastData)
        }
    }

    // MARK: - Hourly Breakdown

    @ViewBuilder
    private func hourlyBreakdownSection(viewModel: StatsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hourly Breakdown")
                .font(.headline)

            if viewModel.hourlyBreakdown.allSatisfy({ $0.count == 0 }) {
                emptyChartPlaceholder(message: "No hourly review data available")
            } else {
                Chart {
                    ForEach(viewModel.hourlyBreakdown, id: \.hour) { item in
                        BarMark(
                            x: .value("Hour", "\(item.hour)h"),
                            y: .value("Reviews", item.count)
                        )
                        .foregroundStyle(Color.indigo.gradient)
                        .cornerRadius(2)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23].map { "\($0)h" }) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }
}
