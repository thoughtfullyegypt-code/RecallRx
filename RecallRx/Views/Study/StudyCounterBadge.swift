import SwiftUI

struct StudyCounterBadge: View {
    let count: Int
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(count, format: .number)
                .bold()
                .monospacedDigit()
            Text(title)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(title) cards remaining")
    }
}
