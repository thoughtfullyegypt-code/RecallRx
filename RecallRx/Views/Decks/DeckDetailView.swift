import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var deck: Deck

    @State private var showingOptions: Bool = false
    @State private var showingAddCard: Bool = false
    @State private var showingRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showingEmptyConfirmation: Bool = false
    @State private var pendingCardDeletionIDs: Set<UUID> = []
    @State private var showingCardDeletionConfirmation = false
    @State private var showingCustomStudySheet: Bool = false
    @State private var showingDrivingMode: Bool = false
    @State private var customStudyNewCount: Int = 10
    @State private var customStudyReviewCount: Int = 20

    var body: some View {
        List {
            // Study Action Hero Section
            Section {
                studyButtonSection
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Due & Total Card Counts Overview
            Section("Card Counts") {
                countsGridView
            }

            // Cards in this Deck Section
            Section {
                if deck.cards.isEmpty {
                    ContentUnavailableView {
                        Label("Your first card starts here", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Add a question and answer to begin building this deck.")
                    } actions: {
                        Button("Add first card", systemImage: "plus") {
                            showingAddCard = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    ForEach(deck.cards.sorted(by: { $0.createdAt > $1.createdAt })) { card in
                        NavigationLink(destination: CardDetailView(card: card)) {
                            deckCardRow(card: card)
                        }
                    }
                    .onDelete(perform: requestCardDeletion)
                }
            } header: {
                Text("Cards (\(deck.cards.count))")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
        .navigationTitle(deck.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add card", systemImage: "plus") {
                    showingAddCard = true
                }

                Menu("Deck options", systemImage: "ellipsis.circle") {
                    Button {
                        showingOptions = true
                    } label: {
                        Label("Deck Options", systemImage: "gearshape")
                    }

                    Button {
                        renameText = deck.name
                        showingRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        rebuildDeck()
                    } label: {
                        Label("Unbury cards", systemImage: "arrow.clockwise")
                    }

                    Button {
                        showingCustomStudySheet = true
                    } label: {
                        Label("Custom Study", systemImage: "slider.horizontal.3")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingEmptyConfirmation = true
                    } label: {
                        Label("Empty Deck", systemImage: "trash")
                    }
                    .disabled(deck.cards.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            DeckOptionsView(deck: deck) {
                dismiss()
            }
        }
        .sheet(isPresented: $showingAddCard) {
            AddCardView(defaultDeck: deck)
        }
        .sheet(isPresented: $showingCustomStudySheet) {
            customStudyView
        }
        .sheet(isPresented: $showingDrivingMode) {
            DrivingModeView(deck: deck)
        }
        .alert("Rename Deck", isPresented: $showingRenameAlert) {
            TextField("Deck Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    deck.name = trimmed
                    deck.modifiedAt = .now
                    try? modelContext.save()
                }
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Empty Deck",
            isPresented: $showingEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All \(deck.cards.count) Cards", role: .destructive) {
                for card in deck.cards {
                    modelContext.delete(card)
                }
                deck.cards.removeAll()
                deck.modifiedAt = .now
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete all cards in '\(deck.name)'? This action cannot be undone.")
        }
        .confirmationDialog(
            "Delete selected cards?",
            isPresented: $showingCardDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button(pendingCardDeletionIDs.count == 1 ? "Delete card" : "Delete cards", role: .destructive, action: deletePendingCards)
            Button("Cancel", role: .cancel) {
                pendingCardDeletionIDs.removeAll()
            }
        } message: {
            Text("This permanently deletes the selected cards and their review history. This action cannot be undone.")
        }
    }

    // MARK: - Study Button Section

    @ViewBuilder
    private var studyButtonSection: some View {
        let totalDue = Scheduler.getDueCards(from: deck).count

        NavigationLink(destination: StudyView(deck: deck)) {
            HStack(spacing: 12) {
                Image(systemName: totalDue > 0 ? "play.circle.fill" : "sparkles")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(totalDue > 0 ? "Study now" : "No cards ready")
                        .font(.headline)
                        .foregroundStyle(AppTheme.onAccent)

                    Text(totalDue > 0 ? "\(totalDue) cards in this session" : (deck.cards.isEmpty ? "Add your first card to begin" : "Come back later or adjust your daily limits"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.onAccent)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.onAccent)
            }
            .foregroundStyle(AppTheme.onAccent)
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppTheme.accent, in: .rect(cornerRadius: 16))
        }
        .disabled(totalDue == 0)
        .padding(.horizontal)
        .padding(.vertical, 8)

        if !deck.cards.isEmpty {
            Button {
                showingDrivingMode = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "car.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hands-free review")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text("Voice review, processed on device")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Counts Grid

    private var countsGridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
            DeckQueueMetricView(title: "New", count: deck.newCards, symbol: "sparkle", color: .blue)
            DeckQueueMetricView(title: "Learning", count: deck.learningCards, symbol: "arrow.triangle.2.circlepath", color: .orange)
            DeckQueueMetricView(title: "Review", count: deck.dueCards, symbol: "checkmark.circle", color: AppTheme.accent)
            DeckQueueMetricView(title: "Total cards", count: deck.totalCards, symbol: "rectangle.stack", color: .purple)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Card Row

    @ViewBuilder
    private func deckCardRow(card: Card) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.front.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                Text(card.state.displayName)
                    .font(.footnote.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cardStateColor(card.state).opacity(0.15))
                    .foregroundStyle(cardStateColor(card.state))
                    .clipShape(Capsule())
            }

            if !card.back.isEmpty {
                Text(card.back.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !card.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(card.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func cardStateColor(_ state: CardState) -> Color {
        switch state {
        case .new: return .blue
        case .learning, .relearning: return .orange
        case .review: return .green
        }
    }

    private func requestCardDeletion(at offsets: IndexSet) {
        let sortedCards = deck.cards.sorted(by: { $0.createdAt > $1.createdAt })
        pendingCardDeletionIDs = Set(offsets.compactMap { index in
            sortedCards.indices.contains(index) ? sortedCards[index].id : nil
        })
        showingCardDeletionConfirmation = !pendingCardDeletionIDs.isEmpty
    }

    private func deletePendingCards() {
        let cardsToDelete = deck.cards.filter { pendingCardDeletionIDs.contains($0.id) }
        for card in cardsToDelete {
            modelContext.delete(card)
        }
        try? modelContext.save()
        pendingCardDeletionIDs.removeAll()
    }

    private func rebuildDeck() {
        Scheduler.unburyAllCards(in: deck)
        deck.modifiedAt = .now
        try? modelContext.save()
    }

    // MARK: - Custom Study View

    private var customStudyView: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Extra New Cards: \(customStudyNewCount)", value: $customStudyNewCount, in: 0...100, step: 5)
                    Stepper("Extra Review Cards: \(customStudyReviewCount)", value: $customStudyReviewCount, in: 0...500, step: 10)
                } header: {
                    Text("Adjust daily study limits")
                } footer: {
                    Text("These changes are saved to this deck. Return to the deck to start a review.")
                }

                Section {
                    Button("Apply study limits") {
                        deck.newCardsPerDay += customStudyNewCount
                        deck.reviewsPerDay += customStudyReviewCount
                        try? modelContext.save()
                        showingCustomStudySheet = false
                    }
                    .bold()
                }
            }
            .navigationTitle("Custom Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingCustomStudySheet = false
                    }
                }
            }
        }
    }
}
