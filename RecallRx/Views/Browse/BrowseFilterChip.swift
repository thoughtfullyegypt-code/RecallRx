import SwiftUI

struct BrowseFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark" : systemImage)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isSelected ? AppTheme.accent.opacity(0.12) : AppTheme.surface)
                .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? AppTheme.accent : AppTheme.border))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
