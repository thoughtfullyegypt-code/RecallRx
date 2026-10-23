import SwiftUI

struct BrowseCardRow: View {
    let card: Card

    private var prompt: String {
        let text = card.front.removingHTMLTags()
        return text.isEmpty ? "Untitled card" : text
    }

    private var stateColor: Color {
        switch card.state {
        case .new: return .blue
        case .learning: return .orange
        case .review: return AppTheme.accent
        case .relearning: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if let deck = card.deck {
                Label(deck.displayName, systemImage: "folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    statusLabel
                    Text("Due \(card.dueDate.relativeDescription.lowercased())")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    statusLabel
                    Text("Due \(card.dueDate.relativeDescription.lowercased())")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: some View {
        Label {
            Text(card.isSuspended ? "Suspended" : card.state.displayName)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: card.isSuspended ? "pause.circle" : "circle.fill")
                .foregroundStyle(card.isSuspended ? Color.orange : stateColor)
                .accessibilityHidden(true)
        }
    }
}
