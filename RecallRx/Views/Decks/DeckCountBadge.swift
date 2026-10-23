import SwiftUI

struct DeckCountBadge: View {
    let count: Int
    let title: LocalizedStringKey
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(count, format: .number)
                .bold()
                .monospacedDigit()
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(count > 0 ? color.opacity(0.10) : AppTheme.secondarySurface,
                    in: .rect(cornerRadius: 8))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
