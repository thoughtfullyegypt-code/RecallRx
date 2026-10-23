import SwiftUI

struct RatingButton: View {
    let rating: SM2Algorithm.Rating
    let intervalText: String?
    let action: () -> Void

    @State private var feedbackTrigger = 0

    private var symbol: String {
        switch rating {
        case .again: return "arrow.counterclockwise"
        case .hard: return "minus.circle"
        case .good: return "checkmark.circle"
        case .easy: return "checkmark.seal"
        }
    }

    private var accessibilityTitle: String {
        if let intervalText, !intervalText.isEmpty {
            return "\(rating.name), next review in \(intervalText)"
        }
        return rating.name
    }

    var body: some View {
        Button(action: rate) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(rating.color)
                    .accessibilityHidden(true)
                Text(rating.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let intervalText, !intervalText.isEmpty {
                    Text(intervalText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .background(rating.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(rating.color.opacity(0.35), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Grades this answer and moves to the next card.")
        .accessibilityInputLabels([rating.name])
        .sensoryFeedback(.impact(weight: .medium), trigger: feedbackTrigger)
    }

    private func rate() {
        feedbackTrigger += 1
        action()
    }
}
