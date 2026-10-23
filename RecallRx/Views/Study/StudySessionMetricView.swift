import SwiftUI

struct StudySessionMetricView: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}
