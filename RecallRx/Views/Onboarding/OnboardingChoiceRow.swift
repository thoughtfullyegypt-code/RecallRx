import SwiftUI

struct OnboardingChoiceRow: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(minHeight: 44)
            .background(isSelected ? AppTheme.accent.opacity(0.1) : AppTheme.surface, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.leading)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
