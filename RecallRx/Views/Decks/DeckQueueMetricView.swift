import SwiftUI

struct DeckQueueMetricView: View {
    let title: LocalizedStringKey
    let count: Int
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(count, format: .number)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
