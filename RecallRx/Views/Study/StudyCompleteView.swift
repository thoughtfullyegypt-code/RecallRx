import SwiftUI

struct StudyCompleteView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let cardsStudied: Int
    let correctCount: Int
    let elapsedTime: TimeInterval
    let onDone: () -> Void
    var onStudyMore: (() -> Void)? = nil

    private var usesInlineActions: Bool {
        verticalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if cardsStudied == 0 {
                    ContentUnavailableView {
                        Label("No cards ready right now", systemImage: "checkmark.circle")
                    } description: {
                        Text("Your daily limits and learning schedules determine what is available. Check back later, or adjust this deck’s limits in Deck Options.")
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(AppTheme.accent)
                            .padding(24)
                            .background(AppTheme.accent.opacity(0.1), in: Circle())
                            .accessibilityHidden(true)
                        Text("Session complete")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("A little practice, lasting progress. No more cards are queued for this session.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        StudySessionMetricView(icon: "rectangle.stack", title: "Reviews", value: cardsStudied.formatted())
                        StudySessionMetricView(icon: "clock", title: "Study time", value: elapsedTime.formattedStudyTime)
                    }
                }
                if usesInlineActions {
                    completionActions
                }
            }
            .frame(maxWidth: AppTheme.contentWidth)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesInlineActions {
                completionActions
                    .background(.bar)
            }
        }
    }

    private var completionActions: some View {
        VStack(spacing: 12) {
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            if let onStudyMore {
                Button("Review buried cards", systemImage: "arrow.clockwise", action: onStudyMore)
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Unburies cards in this deck and starts another session.")
            }
        }
        .frame(maxWidth: AppTheme.contentWidth)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
