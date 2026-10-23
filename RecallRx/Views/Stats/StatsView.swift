import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]
    @State private var viewModel: StatsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Small sessions. Lasting progress.")
                                    .font(.title2.bold())
                                Text("See what you’ve practiced and plan what comes next.")
                                    .foregroundStyle(.secondary)
                            }
                            StatsFiltersView(viewModel: viewModel, decks: decks)
                            StatsOverviewCard(viewModel: viewModel)
                            StatsReviewCharts(viewModel: viewModel)
                            StatsCardDistributionView(distribution: viewModel.cardStateDistribution)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your study rhythm")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                HeatmapView(data: viewModel.heatmapData)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Coming up")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                Text("Scheduled cards for the next 30 days. Future reviews can change these dates.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                ForecastChartView(data: viewModel.forecastData)
                            }
                        }
                        .frame(maxWidth: AppTheme.contentWidth)
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .refreshable { viewModel.fetchData() }
                } else {
                    ProgressView("Loading your progress…")
                }
            }
            .background(AppTheme.canvas)
            .navigationTitle("Progress")
            .task {
                if viewModel == nil {
                    viewModel = StatsViewModel(modelContext: modelContext)
                } else {
                    viewModel?.fetchData()
                }
            }
        }
    }
}
