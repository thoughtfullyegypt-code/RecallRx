import SwiftUI

struct SettingsFSRSPersonalizationSection: View {
    let isOptimized: Bool
    let isOptimizing: Bool
    let lossReduction: Double
    let sampleCount: Int
    let reviewCount: Int
    let minimumRequiredReviews: Int
    let onOptimize: () -> Void
    let onReset: () -> Void

    private var hasEnoughReviews: Bool {
        reviewCount >= minimumRequiredReviews
    }

    var body: some View {
        Section {
            LabeledContent("Memory Parameters", value: isOptimized ? "Personalized" : "Default Weights")
            DisclosureGroup("Personalize FSRS Parameters") {
                VStack(alignment: .leading, spacing: 16) {
                    if isOptimized {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Log-Loss Improvement", value: "\(lossReduction.formatted(.number.precision(.fractionLength(1))))%")
                            LabeledContent("Trained Reviews", value: sampleCount.formatted())
                        }
                        .font(.subheadline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review History")
                            .font(.headline)
                        Text("\(reviewCount.formatted()) reviews · \(minimumRequiredReviews.formatted()) required")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: min(1.0, Double(reviewCount) / Double(minimumRequiredReviews)))
                            .accessibilityLabel("Reviews for personalization")
                            .accessibilityValue("\(reviewCount) of \(minimumRequiredReviews)")
                        Text(hasEnoughReviews
                             ? "You have enough review history to personalize your memory parameters."
                             : "Personalization requires at least 1,000 real reviews to avoid overfitting. Default weights are used until then.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: onOptimize) {
                        HStack {
                            if isOptimizing {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                            Text(isOptimizing ? "Optimizing Parameters…" : (isOptimized ? "Re-optimize Parameters" : "Optimize Parameters"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isOptimizing || !hasEnoughReviews)

                    if isOptimized {
                        Button("Reset to Default Weights", systemImage: "arrow.counterclockwise", role: .destructive, action: onReset)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("FSRS Personalization")
        } footer: {
            Text("Optional tuning based on your own review history. Calculated entirely on this device.")
        }
    }
}
