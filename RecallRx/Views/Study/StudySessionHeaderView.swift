import SwiftUI

struct StudySessionHeaderView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let studiedCount: Int
    let remainingCount: Int
    let newCount: Int
    let learningCount: Int
    let reviewCount: Int
    let cardStartTime: Date
    let showTimer: Bool

    private var totalCount: Int { max(1, studiedCount + remainingCount) }

    private var summaryLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryLayout {
                Text("\(studiedCount) studied · \(remainingCount) remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
                if showTimer {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Label {
                            Text("\(max(0, Int(timeline.date.timeIntervalSince(cardStartTime))))s")
                        } icon: {
                            Image(systemName: "stopwatch")
                        }
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Time on this card")
                        .accessibilityValue("\(max(0, Int(timeline.date.timeIntervalSince(cardStartTime)))) seconds")
                    }
                }
            }

            ProgressView(value: Double(studiedCount), total: Double(totalCount))
                .tint(AppTheme.accent)
                .accessibilityLabel("Session progress")
                .accessibilityValue("\(studiedCount) reviews completed, \(remainingCount) cards remaining")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    StudyCounterBadge(count: newCount, color: .blue, title: "New")
                    StudyCounterBadge(count: learningCount, color: .orange, title: "Learning")
                    StudyCounterBadge(count: reviewCount, color: .green, title: "Review")
                }
                VStack(alignment: .leading, spacing: 8) {
                    StudyCounterBadge(count: newCount, color: .blue, title: "New")
                    StudyCounterBadge(count: learningCount, color: .orange, title: "Learning")
                    StudyCounterBadge(count: reviewCount, color: .green, title: "Review")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
