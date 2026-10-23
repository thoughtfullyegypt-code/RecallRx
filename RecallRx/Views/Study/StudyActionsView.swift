import SwiftUI

struct StudyActionsView: View {
    let isShowingAnswer: Bool
    let intervalStrings: [SM2Algorithm.Rating: String]
    let undoMessage: String?
    let swipeGradingEnabled: Bool
    let disableSwipeUpEasy: Bool
    let onShowAnswer: () -> Void
    let onRate: (SM2Algorithm.Rating) -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let undoMessage {
                HStack(spacing: 12) {
                    Text(undoMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

            if isShowingAnswer {
                Text("How well did you remember?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                RatingButtonsView(intervalStrings: intervalStrings, onRate: onRate)
                if swipeGradingEnabled {
                    Text(disableSwipeUpEasy ? "Swipe: ← Again · ↓ Hard · → Good" : "Swipe: ← Again · ↓ Hard · → Good · ↑ Easy")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("Recall your answer before revealing it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onShowAnswer) {
                    Label("Show answer", systemImage: "arrow.turn.down.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Reveals the answer. Your card is graded only after you choose a rating.")
            }
        }
        .frame(maxWidth: AppTheme.contentWidth)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
