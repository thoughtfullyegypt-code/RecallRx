import SwiftUI

struct StatsOverviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let viewModel: StatsViewModel

    private var speed: String {
        guard viewModel.totalStudyTimeToday > 0 else { return "—" }
        let rate = Double(viewModel.totalReviewsToday) / (viewModel.totalStudyTimeToday / 60)
        return rate.formatted(.number.precision(.fractionLength(1)))
    }

    private var recallRate: String {
        guard !viewModel.periodFilteredLogs.isEmpty else { return "—" }
        return (viewModel.retentionRate / 100).formatted(.percent.precision(.fractionLength(1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(viewModel.streakDays == 1 ? "1-day streak" : "\(viewModel.streakDays)-day streak", systemImage: "flame")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text(viewModel.streakDays > 0
                 ? "A little practice each day adds up."
                 : "Your next review is the start of a new streak.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                StatsMetricTile(title: "Reviews completed", value: viewModel.totalReviewsToday.formatted(), symbol: "checkmark.rectangle.stack")
                StatsMetricTile(title: "Time studying", value: viewModel.totalStudyTimeToday.formattedStudyTime, symbol: "clock")
                StatsMetricTile(title: "Reviews per minute", value: speed, symbol: "gauge.with.dots.needle.33percent")
                StatsMetricTile(title: "Recall rate · \(viewModel.selectedPeriod.rawValue)", value: recallRate, symbol: "brain.head.profile")
            }
            if viewModel.totalReviewsToday == 0 {
                Label("No reviews today yet. Study a deck to see your session here.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Today’s reviews: \(viewModel.todayNewCards) new · \(viewModel.todayLearningCards) learning · \(viewModel.todayReviewCards) review")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Recall rate is the share of reviews rated Hard, Good, or Easy during the selected history period.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
    }
}
