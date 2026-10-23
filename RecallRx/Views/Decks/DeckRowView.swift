import SwiftUI

struct DeckRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let deck: Deck
    var newCount: Int? = nil
    var learningCount: Int? = nil
    var reviewCount: Int? = nil

    private var resolvedNew: Int { newCount ?? deck.newCards }
    private var resolvedLearning: Int { learningCount ?? deck.learningCards }
    private var resolvedReview: Int { reviewCount ?? deck.dueCards }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.accent.opacity(0.10), in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !deck.descriptionText.isEmpty {
                        Text(deck.descriptionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    DeckCountBadge(count: resolvedNew, title: "New", color: .blue)
                    DeckCountBadge(count: resolvedLearning, title: "Learning", color: .orange)
                    DeckCountBadge(count: resolvedReview, title: "Review", color: AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DeckCountBadge(count: resolvedNew, title: "New", color: .blue)
                    DeckCountBadge(count: resolvedLearning, title: "Learning", color: .orange)
                    DeckCountBadge(count: resolvedReview, title: "Review", color: AppTheme.accent)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
