import SwiftUI

struct OnboardingStepHeader: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accent)
                .padding()
                .background(AppTheme.accent.opacity(0.1), in: .rect(cornerRadius: 20))
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
