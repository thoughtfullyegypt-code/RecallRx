import SwiftUI
import SwiftData

struct DeckOptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var deck: Deck
    var onDeckDeleted: (() -> Void)? = nil
    
    @AppStorage("autoPlayAudio") private var autoPlayAudio: Bool = true
    
    @State private var showingRenameAlert: Bool = false
    @State private var newNameText: String = ""
    @State private var showingEmptyConfirmation: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Limits") {
                    Stepper(value: $deck.newCardsPerDay, in: 0...9999, step: 5) {
                        HStack {
                            Text("New Cards/Day")
                            Spacer()
                            Text("\(deck.newCardsPerDay)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Stepper(value: $deck.reviewsPerDay, in: 0...9999, step: 10) {
                        HStack {
                            Text("Maximum Reviews/Day")
                            Spacer()
                            Text("\(deck.reviewsPerDay)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Learning Steps") {
                    HStack {
                        Text("Learning Steps")
                        Spacer()
                        Text("1m, 10m")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Graduating Interval")
                        Spacer()
                        Text("1 day")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Easy Interval")
                        Spacer()
                        Text("4 days")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Starting Ease")
                        Spacer()
                        Text("250%")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Audio & Media") {
                    Toggle("Auto-Play Audio", isOn: $autoPlayAudio)
                }
                
                Section("Deck Actions") {
                    Button {
                        newNameText = deck.name
                        showingRenameAlert = true
                    } label: {
                        Label("Rename Deck", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        showingEmptyConfirmation = true
                    } label: {
                        Label("Empty Cards (\(deck.cards.count))", systemImage: "trash")
                    }
                    .disabled(deck.cards.isEmpty)
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Deck", systemImage: "trash.fill")
                    }
                }
            }
            .navigationTitle("Deck Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        deck.modifiedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                    .bold()
                }
            }
            .alert("Rename Deck", isPresented: $showingRenameAlert) {
                TextField("Deck Name", text: $newNameText)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    let trimmed = newNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        deck.name = trimmed
                        deck.modifiedAt = .now
                        try? modelContext.save()
                    }
                }
            }
            .confirmationDialog(
                "Empty Deck",
                isPresented: $showingEmptyConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All \(deck.cards.count) Cards", role: .destructive) {
                    emptyCards()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete all cards in '\(deck.name)'? This action cannot be undone.")
            }
            .confirmationDialog(
                "Delete Deck",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Deck and Cards", role: .destructive) {
                    deleteDeck()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete '\(deck.name)' and its \(deck.cards.count) cards? This action cannot be undone.")
            }
        }
    }
    
    private func emptyCards() {
        for card in deck.cards {
            modelContext.delete(card)
        }
        deck.cards.removeAll()
        deck.modifiedAt = .now
        try? modelContext.save()
    }
    
    private func deleteDeck() {
        for card in deck.cards {
            modelContext.delete(card)
        }
        modelContext.delete(deck)
        try? modelContext.save()
        onDeckDeleted?()
        dismiss()
    }
}
