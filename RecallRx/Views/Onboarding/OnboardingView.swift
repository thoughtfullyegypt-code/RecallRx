import SwiftUI

/// A short, optional setup for exam goals and study planning preferences.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("userTargetExam") private var userTargetExam = "USMLE Step 1"
    @AppStorage("userDailyNewLimit") private var userDailyNewLimit = 20
    @AppStorage("userDailyReviewLimit") private var userDailyReviewLimit = 200
    @AppStorage("fsrsTargetRetention") private var fsrsTargetRetention = 0.88
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep = 0

    private let exams = [
        "USMLE Step 1 (Pass/Fail)", "USMLE Step 2 CK (Scored)",
        "COMLEX Level 1 / 2", "Clinical Shelf Exams", "MCAT / Pre-Med"
    ]
    private let dailyOptions = [
        (new: 15, review: 150, title: "Light", detail: "A lighter pace for busy rotations."),
        (new: 20, review: 200, title: "Standard", detail: "A starting point for a regular study routine."),
        (new: 30, review: 300, title: "Intensive", detail: "More new material for dedicated study time.")
    ]
    private let retentionPresets = [
        (value: 0.85, title: "85% · Balanced", detail: "A lower target generally means fewer reviews."),
        (value: 0.88, title: "88% · Recommended", detail: "A balance between review workload and recall."),
        (value: 0.90, title: "90% · Higher recall", detail: "A higher target generally means more reviews.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Step \(currentStep + 1) of 4")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.accent)
                        ProgressView(value: Double(currentStep + 1), total: 4)
                            .accessibilityLabel("Setup progress")
                            .accessibilityValue("Step \(currentStep + 1) of 4")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Setup progress")
                    .accessibilityValue("Step \(currentStep + 1) of 4")

                    switch currentStep {
                    case 0:
                        OnboardingStepHeader(symbol: "cross.case", title: "Make room for what matters", detail: "Choose an exam goal for your setup. You can adjust each deck’s workload and review settings in Deck Options.")
                        VStack(spacing: 12) {
                            ForEach(exams, id: \.self) { exam in
                                OnboardingChoiceRow(title: exam, isSelected: userTargetExam == exam || (userTargetExam == "USMLE Step 1" && exam.hasPrefix("USMLE Step 1"))) {
                                    userTargetExam = exam
                                }
                            }
                        }
                    case 1:
                        OnboardingStepHeader(symbol: "calendar", title: "Plan your daily pace", detail: "Choose a suggested starting point for your routine. This saves a planning preference; set each deck’s actual daily limits in Deck Options.")
                        VStack(spacing: 12) {
                            ForEach(dailyOptions, id: \.new) { option in
                                OnboardingChoiceRow(title: "\(option.title) · \(option.new) new / day", detail: "Suggested pace: \(option.new) new cards and \(option.review) reviews per day. \(option.detail)", isSelected: userDailyNewLimit == option.new) {
                                    userDailyNewLimit = option.new
                                    userDailyReviewLimit = option.review
                                }
                            }
                        }
                    case 2:
                        OnboardingStepHeader(symbol: "brain.head.profile", title: "Choose a recall target", detail: "FSRS uses your reviews to estimate when to show each card again. This is a scheduling target, not a guaranteed result.")
                        VStack(spacing: 12) {
                            ForEach(retentionPresets, id: \.value) { preset in
                                OnboardingChoiceRow(title: preset.title, detail: preset.detail, isSelected: abs(fsrsTargetRetention - preset.value) < 0.005) {
                                    fsrsTargetRetention = preset.value
                                }
                            }
                        }
                    default:
                        OnboardingStepHeader(symbol: "checkmark.seal", title: "Your next session starts here", detail: "Choose a deck, try to recall the answer, then rate how well you remembered it. RecallRx schedules the next review.")
                        VStack(spacing: 20) {
                            OnboardingFeatureRow(symbol: "rectangle.stack", title: "Study offline", detail: "Your cards and review history are stored on this device.")
                            OnboardingFeatureRow(symbol: "waveform", title: "Hands-free review", detail: "Optional audio review is available from a deck, with on-device speech recognition.")
                            OnboardingFeatureRow(symbol: "gamecontroller", title: "Review your way", detail: "Use touch controls or connect a compatible Bluetooth controller.")
                            OnboardingFeatureRow(symbol: "arrow.triangle.2.circlepath", title: "Keep your library with you", detail: "Optional iCloud sync and local backups are available in Settings.")
                        }
                        .padding()
                        .background(AppTheme.surface, in: .rect(cornerRadius: AppTheme.cornerRadius))
                        Text("All core study features are free.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .id(currentStep)
                .frame(maxWidth: 600)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.canvas)
            .navigationTitle("Welcome to RecallRx")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set up later", action: completeOnboarding)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(action: advance) {
                        Label(currentStep == 3 ? "Open my decks" : "Continue", systemImage: currentStep == 3 ? "rectangle.stack" : "arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    if currentStep > 0 {
                        Button("Back", action: goBack)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .frame(maxWidth: 600)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
    }

    private func advance() {
        guard currentStep < 3 else {
            completeOnboarding()
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            currentStep += 1
        }
    }

    private func goBack() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            currentStep = max(0, currentStep - 1)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}
