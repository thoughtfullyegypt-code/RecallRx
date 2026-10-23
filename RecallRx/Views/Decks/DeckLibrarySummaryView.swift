import SwiftUI

struct DeckLibrarySummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let decks: [Deck]

    var body: some View {
        let now = Date()
        let queues = decks.map { (deck: $0, cards: Scheduler.getDueCards(from: $0, now: now)) }
        let readyCards = queues.flatMap { $0.cards }
        let newCount = readyCards.filter { $0.state == .new }.count
        let learningCount = readyCards.filter { $0.state == .learning || $0.state == .relearning }.count
        let reviewCount = readyCards.filter { $0.state == .review }.count
        let nextDeck = queues.first { !$0.cards.isEmpty }?.deck
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("TODAY", systemImage: "sun.max")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)

                Text(nextDeck == nil ? "Room to recharge." : "A little progress, every day.")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text(nextDeck == nil
                     ? "No cards are ready within your daily limits. Come back later or adjust a deck’s study limits."
                     : "Keep clinical knowledge fresh for USMLE, COMLEX, and shelf exams. Your cards are ready offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                DeckQueueMetricView(title: "New", count: newCount, symbol: "sparkle", color: .blue)
                DeckQueueMetricView(title: "Learning", count: learningCount, symbol: "arrow.triangle.2.circlepath", color: .orange)
                DeckQueueMetricView(title: "Review", count: reviewCount, symbol: "checkmark.circle", color: AppTheme.accent)
            }

            if let deck = nextDeck {
                NavigationLink(destination: StudyView(deck: deck)) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start a review").font(.headline)
                            Text(deck.displayName).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(AppTheme.onAccent)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(AppTheme.accent, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Study the ready cards in this deck")
            }
        }
        .padding(.vertical, 4)
    }
}
