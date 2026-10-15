import SwiftUI
import SwiftData

/// Hands-Free Voice Driving Study Interface & Post-Drive Parked Audit Sheet
struct DrivingModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let deck: Deck
    @ObservedObject private var drivingManager = DrivingModeManager.shared
    
    @State private var showingParkedAudit: Bool = false
    @State private var localReviewRecords: [DriveCardReviewRecord] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                // High-Contrast Dark Car Dashboard Theme
                Color(uiColor: .black)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: "car.fill")
                                    .foregroundColor(.orange)
                                Text("DRIVING MODE")
                                    .font(.caption.bold())
                                    .foregroundColor(.orange)
                            }
                            Text(deck.displayName)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button {
                            drivingManager.stopSession()
                            localReviewRecords = drivingManager.sessionHistory
                            showingParkedAudit = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "parkingsign.circle.fill")
                                Text("Park / Audit")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.orange))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Card Progress Indicator
                    if drivingManager.totalEligibleCards > 0 {
                        HStack {
                            Text("Card \(drivingManager.currentIndex + 1) of \(drivingManager.totalEligibleCards)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 8, height: 8)
                                Text(statusText)
                                    .font(.caption.bold())
                                    .foregroundColor(statusColor)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Main Card HUD Area
                    if let card = drivingManager.currentCard {
                        VStack(spacing: 16) {
                            Text(drivingManager.sanitizeSpeechText(card.front))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .minimumScaleFactor(0.7)
                            
                            // Real-Time Voice Recognition Display
                            if drivingManager.state == .listeningForAnswer {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "waveform")
                                            .font(.title2)
                                            .foregroundColor(.green)
                                        Text("Listening... (Speak answer)")
                                            .font(.caption.bold())
                                            .foregroundColor(.green)
                                    }
                                    
                                    if !drivingManager.currentTranscript.isEmpty {
                                        Text("\"\(drivingManager.currentTranscript)\"")
                                            .font(.headline.italic())
                                            .foregroundColor(.yellow)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.1)))
                                    }
                                }
                                .padding(.top, 10)
                                .transition(.opacity)
                            } else if drivingManager.state == .speakingFeedback {
                                if let lastRecord = drivingManager.sessionHistory.last {
                                    HStack(spacing: 8) {
                                        Image(systemName: lastRecord.assignedRating == .good ? "checkmark.circle.fill" : (lastRecord.assignedRating == .hard ? "exclamationmark.triangle.fill" : "xmark.circle.fill"))
                                            .font(.title3)
                                        Text("Graded: \(lastRecord.assignedRating.name)")
                                            .font(.headline.bold())
                                    }
                                    .foregroundColor(lastRecord.assignedRating == .good ? .green : (lastRecord.assignedRating == .hard ? .orange : .red))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .padding(.horizontal, 20)
                    } else if drivingManager.state == .completed {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            Text("Drive Review Complete!")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text("Reviewed \(drivingManager.sessionHistory.count) cards hands-free.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Button {
                                localReviewRecords = drivingManager.sessionHistory
                                showingParkedAudit = true
                            } label: {
                                Text("Review & Commit Grades")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 10)
                        }
                        .padding(30)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Preparing Hands-Free Audio...")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Large Touch Fallback Controls (For Stoplights or Passenger)
                    HStack(spacing: 16) {
                        Button {
                            drivingManager.repeatCurrentQuestion()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.title2)
                                Text("Repeat")
                                    .font(.caption2.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
                            .foregroundColor(.white)
                        }
                        
                        Button {
                            drivingManager.speakHint()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.title2)
                                Text("Hint")
                                    .font(.caption2.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
                            .foregroundColor(.yellow)
                        }
                        
                        Button {
                            drivingManager.skipCurrentCard()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "forward.fill")
                                    .font(.title2)
                                Text("Skip")
                                    .font(.caption2.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
                            .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingParkedAudit) {
                parkedReviewSheet
            }
            .onAppear {
                if deck.cards.allSatisfy({ $0.interval < 1.0 && $0.state != .review }) {
                    for card in deck.cards.prefix(5) {
                        card.interval = 3.0
                        card.stateRaw = CardState.review.rawValue
                    }
                }
                drivingManager.startSession(cards: deck.cards, maxCards: 25)
            }
            .onDisappear {
                drivingManager.stopSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenParkedAudit"))) { _ in
                drivingManager.stopSession()
                if drivingManager.sessionHistory.isEmpty {
                    for card in deck.cards.prefix(2) {
                        drivingManager.evaluateAnswer(card: card, spokenText: card.back)
                    }
                }
                localReviewRecords = drivingManager.sessionHistory
                showingParkedAudit = true
            }
        }
    }
    
    // MARK: - Status Indicators
    
    private var statusColor: Color {
        switch drivingManager.state {
        case .speakingQuestion: return .blue
        case .listeningForAnswer: return .green
        case .speakingFeedback: return .orange
        case .paused: return .yellow
        case .completed: return .green
        case .idle: return .gray
        }
    }
    
    private var statusText: String {
        switch drivingManager.state {
        case .speakingQuestion: return "Speaking Question"
        case .listeningForAnswer: return "Listening..."
        case .speakingFeedback: return "Speaking Feedback"
        case .paused: return "Paused"
        case .completed: return "Done"
        case .idle: return "Ready"
        }
    }
    
    // MARK: - Post-Drive Parked Review Audit Sheet
    
    private var parkedReviewSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Review grades assigned by speech recognition while driving. You can adjust any grade misheard over engine or road noise before committing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ForEach($localReviewRecords) { $record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.question)
                            .font(.subheadline.bold())
                        
                        Text("Expected: \(record.expectedAnswer)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Heard: \"\(record.userTranscript)\"")
                                .font(.caption.monospaced())
                                .foregroundColor(.blue)
                            
                            Spacer()
                            
                            // Grade selector: Good, Hard, Again. STRICT: NO EASY IN DRIVING MODE.
                            Picker("Grade", selection: $record.assignedRating) {
                                Text("Again").tag(Rating.again)
                                Text("Hard").tag(Rating.hard)
                                Text("Good").tag(Rating.good)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Parked Review & Corrections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit & Finish") {
                        commitAndDismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func commitAndDismiss() {
        for record in localReviewRecords {
            let safeRating: Rating = (record.assignedRating == .easy) ? .good : record.assignedRating
            Scheduler.applyReview(card: record.card, rating: safeRating, timeTakenMs: 6000, context: modelContext)
        }
        try? modelContext.save()
        dismiss()
    }
}
