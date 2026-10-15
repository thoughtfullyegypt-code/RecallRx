import SwiftUI

struct RatingButtonsView: View {
    let intervalStrings: [SM2Algorithm.Rating: String]
    let onRate: (SM2Algorithm.Rating) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(SM2Algorithm.Rating.allCases) { rating in
                RatingButton(
                    rating: rating,
                    intervalText: intervalStrings[rating] ?? "",
                    action: { onRate(rating) }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct RatingButton: View {
    let rating: SM2Algorithm.Rating
    let intervalText: String
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Text(intervalText.isEmpty ? "-" : intervalText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(rating.color)
                    .lineLimit(1)
                
                Text(rating.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(rating.color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(rating.color.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(RatingScaleButtonStyle())
    }
}

private struct RatingScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
