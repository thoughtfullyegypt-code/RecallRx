import SwiftUI
import SwiftData

/// Shelf Exam Cram & Filtered Deck Configuration Sheet
struct FilteredDeckConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Deck.name) private var decks: [Deck]
    
    @State private var cramName: String = "Shelf Exam Cram"
    @State private var searchSyntaxQuery: String = "is:due"
    @State private var cardLimit: Int = 50
    @State private var cramOrder: FilteredDeckConfig.CramOrder = .dueFirst
    @State private var rescheduleCards: Bool = false // False = Safe Cram Mode (does not corrupt FSRS intervals)
    
    // Exam-Date Target Scheduler
    @State private var showExamScheduler: Bool = true
    @State private var targetExamDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var selectedDeckForPace: Deck? = nil
    
    @State private var matchingCardCount: Int = 0
    @State private var isStartingSession: Bool = false
    @State private var activeStudyDeck: Deck? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Cram Session Settings
                Section("Shelf Cram Target") {
                    TextField("Session Name", text: $cramName)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Search Syntax / Tag Filter:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g. tag:Cardio is:due", text: $searchSyntaxQuery)
                            .font(.system(.subheadline, design: .monospaced))
                            .onChange(of: searchSyntaxQuery) { _, _ in
                                updateMatchingCount()
                            }
                        
                        // Quick filter chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                filterChip("is:due", label: "Due Today")
                                filterChip("is:new", label: "New Cards")
                                filterChip("is:learning", label: "Learning")
                                filterChip("tag:Cardio", label: "#Cardio")
                                filterChip("tag:Neuro", label: "#Neuro")
                                filterChip("tag:Micro", label: "#Micro")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    Stepper("Card Limit: \(cardLimit) cards", value: $cardLimit, in: 10...300, step: 10)
                        .onChange(of: cardLimit) { _, _ in
                            updateMatchingCount()
                        }
                    
                    Picker("Review Order", selection: $cramOrder) {
                        ForEach(FilteredDeckConfig.CramOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                }
                
                // Section 2: Scheduling Safety (FSRS Protection)
                Section {
                    Toggle("Reschedule Cards Based on Answers", isOn: $rescheduleCards)
                } header: {
                    Text("Interval Scheduling Mode")
                } footer: {
                    Text(rescheduleCards
                         ? "⚠️ Standard Mode: Ratings will update permanent card intervals and stability."
                         : "🛡️ Safe Cram Mode: Ratings will NOT alter long-term FSRS intervals. Review freely without breaking spaced repetition schedules.")
                }
                
                // Section 3: Exam-Date Target Scheduler (Reddit / RemNote Feature)
                Section {
                    Toggle("Enable Exam-Date Pace Planner", isOn: $showExamScheduler)
                    
                    if showExamScheduler {
                        DatePicker("Target Exam Date", selection: $targetExamDate, displayedComponents: .date)
                        
                        if let deck = selectedDeckForPace ?? decks.first {
                            let pace = FilteredDeckManager.calculateExamPace(examDate: targetExamDate, deck: deck)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Days Remaining")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(pace.daysRemaining) days")
                                            .font(.headline.bold())
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Target Daily Pace")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(pace.recommendedDailyNew) new/day")
                                            .font(.headline.bold())
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Text(pace.message)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                    Text("Recommended Target Retention: \(Int(pace.recommendedRetention * 100))%")
                                        .font(.caption.bold())
                                        .foregroundColor(.primary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Exam-Date Target Scheduler")
                } footer: {
                    Text("Calculates required daily new card pacing to mature all cards before your Step 1/2 or Shelf exam.")
                }
                
                // Section 4: Action Button
                Section {
                    Button {
                        startCramSession()
                    } label: {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.red)
                            Text("Start Cram Session (\(matchingCardCount) cards)")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(matchingCardCount == 0)
                }
            }
            .navigationTitle("Shelf Cram & Custom Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if selectedDeckForPace == nil {
                    selectedDeckForPace = decks.first
                }
                updateMatchingCount()
            }
            .fullScreenCover(item: $activeStudyDeck) { deck in
                StudyView(deck: deck)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func filterChip(_ query: String, label: String) -> some View {
        Button {
            searchSyntaxQuery = query
            updateMatchingCount()
        } label: {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(searchSyntaxQuery == query ? Color.blue : Color(.secondarySystemBackground))
                .foregroundColor(searchSyntaxQuery == query ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func updateMatchingCount() {
        let allCards = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let config = FilteredDeckConfig(
            name: cramName,
            searchFilter: searchSyntaxQuery,
            cardLimit: cardLimit,
            rescheduleCards: rescheduleCards,
            order: cramOrder
        )
        let filtered = FilteredDeckManager.buildFilteredCards(config: config, allCards: allCards)
        matchingCardCount = filtered.count
    }
    
    private func startCramSession() {
        let allCards = (try? modelContext.fetch(FetchDescriptor<Card>())) ?? []
        let config = FilteredDeckConfig(
            name: cramName,
            searchFilter: searchSyntaxQuery,
            cardLimit: cardLimit,
            rescheduleCards: rescheduleCards,
            order: cramOrder
        )
        let filtered = FilteredDeckManager.buildFilteredCards(config: config, allCards: allCards)
        
        guard !filtered.isEmpty else { return }
        
        // Create an ephemeral cram deck
        let cramDeck = Deck(name: "🔥 \(cramName)", deckDescription: "Cram Filter: \(searchSyntaxQuery)")
        cramDeck.cards = filtered
        
        activeStudyDeck = cramDeck
    }
}
