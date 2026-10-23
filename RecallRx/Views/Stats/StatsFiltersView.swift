import SwiftUI

struct StatsFiltersView: View {
    @Bindable var viewModel: StatsViewModel
    let decks: [Deck]

    var body: some View {
        VStack(spacing: 0) {
            LabeledContent("Deck") {
                Picker("Deck", selection: $viewModel.selectedDeck) {
                    Text("All decks").tag(nil as Deck?)
                    ForEach(decks, id: \.id) { deck in
                        Text(deck.name).tag(Optional(deck))
                    }
                }
                .labelsHidden()
                .frame(minHeight: 44)
            }
            Divider()
            LabeledContent("History") {
                Picker("Review history", selection: $viewModel.selectedPeriod) {
                    ForEach(StatsPeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .labelsHidden()
                .frame(minHeight: 44)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
    }
}
