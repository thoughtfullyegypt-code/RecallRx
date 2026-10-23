import SwiftUI
import SwiftData

struct AddDeckView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var viewModel: DeckViewModel?
    var initialParentDeckID: UUID?

    @Query(sort: \Deck.name) private var allDecks: [Deck]
    @FocusState private var isNameFocused: Bool

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedParentDeckID: UUID?
    @State private var newCardsPerDay: Int = 20
    @State private var reviewsPerDay: Int = 200
    @State private var showingDiscardConfirmation = false

    init(viewModel: DeckViewModel? = nil, initialParentDeckID: UUID? = nil) {
        self.viewModel = viewModel
        self.initialParentDeckID = initialParentDeckID
        self._selectedParentDeckID = State(initialValue: initialParentDeckID)
    }

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        !name.isEmpty || !descriptionText.isEmpty
            || selectedParentDeckID != initialParentDeckID
            || newCardsPerDay != 20 || reviewsPerDay != 200
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { isNameFocused = false }
                        .accessibilityLabel("Deck name, required")

                    TextField("What will you study? (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Deck description, optional")
                } header: {
                    Text("Give your deck a name")
                } footer: {
                    Text("Try a subject or topic, like Cardiology or Step 1 review.")
                }

                Section {
                    Picker("Location", selection: $selectedParentDeckID) {
                        Text("My decks")
                            .tag(nil as UUID?)

                        ForEach(availableParentDecks) { deck in
                            Text(deck.name)
                                .tag(deck.id as UUID?)
                        }
                    }
                } header: {
                    Text("Keep it organized")
                } footer: {
                    Text("Choose an existing deck to create a subdeck inside it.")
                }

                if viewModel == nil {
                    Section {
                        Stepper(value: $newCardsPerDay, in: 0...9999, step: 5) {
                            LabeledContent("New cards per day") {
                                Text(newCardsPerDay, format: .number).monospacedDigit()
                            }
                        }
                        Stepper(value: $reviewsPerDay, in: 0...9999, step: 10) {
                            LabeledContent("Reviews per day") {
                                Text(reviewsPerDay, format: .number).monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Set a comfortable pace")
                    } footer: {
                        Text("Daily limits help keep each session manageable. You can change them in Deck Options.")
                    }
                } else {
                    Section {
                        Label("Start with 20 new cards and up to 200 reviews per day.", systemImage: "leaf")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Adjust your daily limits in Deck Options after creating your deck.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(AppTheme.canvas)
            .navigationTitle("New deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: saveDeck)
                        .bold()
                        .disabled(isSaveDisabled)
                }
            }
            .confirmationDialog("Discard this deck?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: {
                Text("Your deck has not been created yet.")
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
        .task { isNameFocused = true }
    }

    private var availableParentDecks: [Deck] {
        if let vm = viewModel { return vm.decks }
        return allDecks
    }

    private func cancel() {
        if hasUnsavedChanges {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
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
