import SwiftUI
import SwiftData

struct AddDeckView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var viewModel: DeckViewModel?
    var initialParentDeckID: UUID?
    
    @Query(sort: \Deck.name) private var allDecks: [Deck]
    
    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedParentDeckID: UUID?
    @State private var newCardsPerDay: Int = 20
    @State private var reviewsPerDay: Int = 200
    
    init(viewModel: DeckViewModel? = nil, initialParentDeckID: UUID? = nil) {
        self.viewModel = viewModel
        self.initialParentDeckID = initialParentDeckID
        self._selectedParentDeckID = State(initialValue: initialParentDeckID)
    }
    
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Deck Info") {
                    TextField("Deck Name", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section("Hierarchy") {
                    Picker("Parent Deck", selection: $selectedParentDeckID) {
                        Text("None (Top-Level Deck)")
                            .tag(nil as UUID?)
                        
                        ForEach(availableParentDecks) { deck in
                            Text(deck.displayName)
                                .tag(deck.id as UUID?)
                        }
                    }
                }
                
                Section("Daily Study Limits") {
                    Stepper(value: $newCardsPerDay, in: 0...9999, step: 5) {
                        HStack {
                            Text("New Cards/Day")
                            Spacer()
                            Text("\(newCardsPerDay)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Stepper(value: $reviewsPerDay, in: 0...9999, step: 10) {
                        HStack {
                            Text("Maximum Reviews/Day")
                            Spacer()
                            Text("\(reviewsPerDay)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDeck()
                    }
                    .bold()
                    .disabled(isSaveDisabled)
                }
            }
        }
    }
    
    private var availableParentDecks: [Deck] {
        if let vm = viewModel {
            return vm.decks
        }
        return allDecks
    }
    
    private func saveDeck() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        if let vm = viewModel {
            vm.addDeck(
                name: trimmedName,
                description: descriptionText,
                parentDeckID: selectedParentDeckID
            )
        } else {
            let newDeck = Deck(
                name: trimmedName,
                descriptionText: descriptionText,
                parentDeckID: selectedParentDeckID,
                newCardsPerDay: newCardsPerDay,
                reviewsPerDay: reviewsPerDay
            )
            modelContext.insert(newDeck)
            try? modelContext.save()
        }
        
        dismiss()
    }
}
