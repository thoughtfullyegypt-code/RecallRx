import SwiftUI

/// First-Run Onboarding Quick Start Flow (< 1 minute setup)
/// Configures target medical exam, daily card limits, and FSRS retention presets
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("userTargetExam") private var userTargetExam: String = "USMLE Step 1"
    @AppStorage("userDailyNewLimit") private var userDailyNewLimit: Int = 20
    @AppStorage("userDailyReviewLimit") private var userDailyReviewLimit: Int = 200
    @AppStorage("fsrsTargetRetention") private var fsrsTargetRetention: Double = 0.88
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: Int = 0
    
    let exams = [
        "USMLE Step 1 (Pass/Fail)",
        "USMLE Step 2 CK (Scored)",
        "COMLEX Level 1 / 2",
        "Clinical Shelf Exams",
        "MCAT / Pre-Med"
    ]
    
    let dailyOptions = [
        (newCount: 15, reviewCount: 150, label: "Light (Busy Hospital Rotations)"),
        (newCount: 20, reviewCount: 200, label: "Standard (Recommended)"),
        (newCount: 30, reviewCount: 300, label: "Intensive (Dedicated Study Period)")
    ]
    
    let retentionPresets = [
        (retention: 0.85, title: "0.85 (Balanced)", subtitle: "15% fewer daily reviews. Ideal for wards and clerkships."),
        (retention: 0.88, title: "0.88 (Optimal)", subtitle: "Recommended balance between long-term retention and daily study time."),
        (retention: 0.90, title: "0.90 (High Mastery)", subtitle: "Target 260+ board scores with maximum memory recall.")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header with Progress Dots
                HStack(spacing: 8) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                
                TabView(selection: $currentStep) {
                    // Step 1: Welcome & Exam Goal
                    stepExamSelection
                        .tag(0)
                    
                    // Step 2: Daily Card Workload
                    stepDailyWorkload
                        .tag(1)
                    
                    // Step 3: FSRS Retention Preset
                    stepRetentionPreset
                        .tag(2)
                    
                    // Step 4: Pro Features Overview
                    stepProOverview
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Bottom Button Bar
                VStack(spacing: 12) {
                    if currentStep < 3 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentStep += 1
                            }
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else {
                        Button {
                            completeOnboarding()
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("Start Studying with RecallRx")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Steps
    
    private var stepExamSelection: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 20)
            
            Text("Welcome to RecallRx")
                .font(.title2.bold())
            
            Text("Select your primary medical exam goal to tailor deck recommendations and search tags.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            VStack(spacing: 10) {
                ForEach(exams, id: \.self) { exam in
                    Button {
                        userTargetExam = exam
                    } label: {
                        HStack {
                            Text(exam)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            if userTargetExam == exam {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(userTargetExam == exam ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(userTargetExam == exam ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    private var stepDailyWorkload: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 20)
            
            Text("Daily Study Pace")
                .font(.title2.bold())
            
            Text("Choose a daily new card limit that fits your clinical rotation schedule.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                ForEach(dailyOptions, id: \.newCount) { option in
                    Button {
                        userDailyNewLimit = option.newCount
                        userDailyReviewLimit = option.reviewCount
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(option.newCount) New Cards / Day")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(option.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if userDailyNewLimit == option.newCount {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(userDailyNewLimit == option.newCount ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(userDailyNewLimit == option.newCount ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    private var stepRetentionPreset: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.top, 20)
            
            Text("FSRS Retention Target")
                .font(.title2.bold())
            
            Text("The modern FSRS-6 algorithm guarantees target recall probability while minimizing daily study card load.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                ForEach(retentionPresets, id: \.retention) { preset in
                    Button {
                        fsrsTargetRetention = preset.retention
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.title)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text(preset.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if abs(fsrsTargetRetention - preset.retention) < 0.005 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(abs(fsrsTargetRetention - preset.retention) < 0.005 ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(abs(fsrsTargetRetention - preset.retention) < 0.005 ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    private var stepProOverview: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.orange)
                .padding(.top, 20)
            
            Text("All Built-In & 100% Free")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(
                    icon: "car.fill",
                    color: .orange,
                    title: "Hands-Free Driving Mode",
                    desc: "Review cards on your commute using on-device voice recognition and fuzzy grading."
                )
                
                FeatureRow(
                    icon: "gamecontroller.fill",
                    color: .green,
                    title: "8BitDo Gamepad Support",
                    desc: "Connect any Bluetooth controller to review cards effortlessly in bed or standing."
                )
                
                FeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue,
                    title: "Local-First Architecture",
                    desc: "100% offline functionality. Your medical study data belongs exclusively to you."
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    private func completeOnboarding() {
        hasCompletedOnboarding = true
        dismiss()
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
