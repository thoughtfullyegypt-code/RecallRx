import SwiftUI

struct StudyCompleteView: View {
    let cardsStudied: Int
    let correctCount: Int
    let elapsedTime: TimeInterval
    let onDone: () -> Void
    var onStudyMore: (() -> Void)? = nil
    
    @State private var isIconAnimated: Bool = false
    @State private var areStatsVisible: Bool = false
    
    private var correctRatePercentage: Int {
        guard cardsStudied > 0 else { return 100 }
        return Int(round(Double(correctCount) / Double(cardsStudied) * 100.0))
    }
    
    private var formattedTime: String {
        let totalSeconds = max(0, Int(elapsedTime))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Celebration Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isIconAnimated ? 1.0 : 0.3)
                    .rotationEffect(.degrees(isIconAnimated ? 0 : -30))
            }
            .padding(.bottom, 8)
            
            // Title & Subtitle
            VStack(spacing: 8) {
                Text("Congratulations!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("You've reviewed all cards due in this deck.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Session Statistics Cards
            HStack(spacing: 12) {
                StatMetricCard(
                    icon: "square.stack.fill",
                    color: .blue,
                    title: "Studied",
                    value: "\(cardsStudied)"
                )
                
                StatMetricCard(
                    icon: "checkmark.seal.fill",
                    color: .green,
                    title: "Retention",
                    value: "\(correctRatePercentage)%"
                )
                
                StatMetricCard(
                    icon: "clock.fill",
                    color: .orange,
                    title: "Time",
                    value: formattedTime
                )
            }
            .padding(.horizontal, 20)
            .opacity(areStatsVisible ? 1.0 : 0.0)
            .offset(y: areStatsVisible ? 0 : 20)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                if let onStudyMore = onStudyMore {
                    Button(action: onStudyMore) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Study More")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemFill))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) {
                isIconAnimated = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                areStatsVisible = true
            }
        }
    }
}

private struct StatMetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
        )
    }
}
