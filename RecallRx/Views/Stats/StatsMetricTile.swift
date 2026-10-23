import SwiftUI

struct StatsMetricTile: View {
    let title: LocalizedStringResource
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(AppTheme.secondarySurface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
    }
}
