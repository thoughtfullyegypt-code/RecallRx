import SwiftUI

struct HeatmapDayButton: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .body) private var dayWidth: CGFloat = 44
    let date: Date
    let count: Int
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    private var intensity: Double {
        switch count {
        case 0: return 0
        case 1...4: return 0.1
        case 5...9: return 0.2
        case 10...19: return 0.3
        default: return 0.4
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.day())
                    .font(.body)
                if differentiateWithoutColor {
                    Text(count.formatted())
                        .font(.caption)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: count > 0 ? "circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isAvailable ? Color.primary : Color.secondary)
            .frame(width: dayWidth, height: dayWidth + 12)
            .background(count > 0 ? AppTheme.accent.opacity(intensity) : AppTheme.secondarySurface, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year()))
        .accessibilityValue(isAvailable ? "\(count) reviews" : "Outside available history")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
