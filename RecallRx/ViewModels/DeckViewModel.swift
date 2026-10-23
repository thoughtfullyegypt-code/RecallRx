import Foundation
import SwiftData
import Observation

@Observable
final class DeckViewModel {
    var modelContext: ModelContext
    var decks: [Deck] = []
    var searchText: String = ""
    private let defaults: UserDefaults

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.defaults = defaults
        fetchDecks()
    }
    
    // MARK: - Deck Fetching
    
    func fetchDecks() {
        do {
            let descriptor = FetchDescriptor<Deck>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            decks = try modelContext.fetch(descriptor)
        } catch {
            decks = []
        }
    }
    
    // MARK: - Deck Hierarchy & Filtering
    
    var topLevelDecks: [Deck] {
        decks
            .filter { $0.parentDeckID == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var filteredDecks: [Deck] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return topLevelDecks
        }
        return topLevelDecks.filter { deckMatchesSearch($0, query: query) }
    }
    
    private func deckMatchesSearch(_ deck: Deck, query: String) -> Bool {
        if deck.name.localizedCaseInsensitiveContains(query) ||
           deck.descriptionText.localizedCaseInsensitiveContains(query) {
            return true
        }
        let subdecks = getSubdecks(for: deck)
        return subdecks.contains { deckMatchesSearch($0, query: query) }
    }
    
    func getSubdecks(for deck: Deck) -> [Deck] {
        decks
            .filter { $0.parentDeckID == deck.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Card & Due Counters
    
    func getTotalCardCount(for deck: Deck) -> Int {
        var total = deck.cards.count
        for subdeck in getSubdecks(for: deck) {
            total += getTotalCardCount(for: subdeck)
        }
        return total
    }
    
    func getDueCount(for deck: Deck, now: Date = .now, calendar: Calendar = .current) -> (new: Int, learning: Int, review: Int) {
        let queue = Scheduler.getDueCards(from: deck, now: now, calendar: calendar)
        var newTotal = queue.filter { $0.state == .new }.count
        var learningTotal = queue.filter { $0.state == .learning || $0.state == .relearning }.count
        var reviewTotal = queue.filter { $0.state == .review }.count
        // Each child has its own independent daily budget. Do not cap the aggregate
        // by the parent's limit after the parent's direct queue has already been limited.
        for subdeck in getSubdecks(for: deck) {
            let subCount = getDueCount(for: subdeck, now: now, calendar: calendar)
            newTotal += subCount.new
            learningTotal += subCount.learning
            reviewTotal += subCount.review
        }
        return (new: newTotal, learning: learningTotal, review: reviewTotal)
    }

    // MARK: - CRUD Operations
    
    func addDeck(name: String, description: String = "", parentDeckID: UUID? = nil,
                 newCardsPerDay: Int? = nil, reviewsPerDay: Int? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let deck = Deck(
            name: trimmed,
            descriptionText: description,
            parentDeckID: parentDeckID,
            newCardsPerDay: max(newCardsPerDay ?? (defaults.object(forKey: "defaultNewCardsPerDay") as? Int) ?? AppConstants.defaultNewCardsPerDay, 0),
            reviewsPerDay: max(reviewsPerDay ?? (defaults.object(forKey: "defaultMaxReviewsPerDay") as? Int) ?? AppConstants.defaultReviewsPerDay, 0)
        )
        modelContext.insert(deck)
        try? modelContext.save()
        fetchDecks()
    }
    
    func deleteDeck(_ deck: Deck) {
        // Recursively delete all child subdecks and their cards
        let subdecks = decks.filter { $0.parentDeckID == deck.id }
        for subdeck in subdecks {
            deleteDeck(subdeck)
        }
        
        // Delete all cards belonging to this deck
        for card in deck.cards {
            modelContext.delete(card)
        }
        
        modelContext.delete(deck)
        try? modelContext.save()
        fetchDecks()
    }
    
    func renameDeck(_ deck: Deck, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        deck.name = trimmed
        deck.modifiedAt = .now
        try? modelContext.save()
        fetchDecks()
    }
    
    func duplicateDeck(_ deck: Deck) {
        let copyName = "\(deck.name) Copy"
        let newDeck = Deck(
            name: copyName,
            descriptionText: deck.descriptionText,
            parentDeckID: deck.parentDeckID,
            newCardsPerDay: deck.newCardsPerDay,
            reviewsPerDay: deck.reviewsPerDay
        )
        modelContext.insert(newDeck)
        
        for originalCard in deck.cards {
            let copiedCard = Card(
                front: originalCard.front,
                back: originalCard.back,
                deck: newDeck,
                tags: originalCard.tags,
                noteType: originalCard.noteType,
                createdAt: .now,
                modifiedAt: .now,
                isSuspended: originalCard.isSuspended,
                isBuried: false,
                lapseCount: 0,
                interval: 0.0,
                easeFactor: originalCard.easeFactor,
                repetitions: 0,
                dueDate: .now,
                lastReviewDate: nil,
                state: .new,
                learningStep: 0
            )
            modelContext.insert(copiedCard)
        }
        
        try? modelContext.save()
        fetchDecks()
    }
    
    func moveDeck(_ deck: Deck, to parent: Deck?) {
        if let parent = parent {
            // Prevent circular parenting or parenting to self
            guard parent.id != deck.id, !isDescendant(deck: parent, of: deck) else {
                return
            }
        }
        deck.parentDeckID = parent?.id
        deck.modifiedAt = .now
        try? modelContext.save()
        fetchDecks()
    }
    
    private func isDescendant(deck: Deck, of ancestor: Deck) -> Bool {
        var currentParentID = deck.parentDeckID
        while let pID = currentParentID {
            if pID == ancestor.id { return true }
            currentParentID = decks.first { $0.id == pID }?.parentDeckID
        }
        return false
    }
}
