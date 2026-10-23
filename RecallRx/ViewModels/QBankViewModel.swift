import Foundation
import SwiftData
import SwiftUI

enum QBankSource: String, CaseIterable, Identifiable {
    case all = "All QBanks"
    case uworld = "UWorld"
    case amboss = "AMBOSS"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .all: return "square.stack.3d.up.fill"
        case .uworld: return "circle.hexagongrid.fill"
        case .amboss: return "cross.case.fill"
        }
    }
}

struct QIDMatchResult: Identifiable {
    let id = UUID()
    let qid: String
    var cards: [Card]
    
    var isFound: Bool { !cards.isEmpty }
    var suspendedCount: Int { cards.filter { $0.isSuspended }.count }
    var unsuspendedCount: Int { cards.filter { !$0.isSuspended }.count }
}

@Observable
final class QBankViewModel {
    var modelContext: ModelContext
    var rawInput: String = ""
    var selectedSource: QBankSource = .all
    var selectedDeck: Deck? = nil
    var availableDecks: [Deck] = []
    
    var matchResults: [QIDMatchResult] = []
    var isSearching: Bool = false
    var customTagInput: String = "UWorld_Incorrects"
    var lastActionMessage: String? = nil
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchDecks()
    }
    
    func fetchDecks() {
        let descriptor = FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.name)])
        if let decks = try? modelContext.fetch(descriptor) {
            self.availableDecks = decks
        }
    }
    
    // MARK: - Parse QIDs from free text
    var parsedQIDs: [String] {
        QuestionIDMatcher.parseInput(rawInput)
    }

    // MARK: - Search
    func searchQIDs() {
        isSearching = true
        defer { isSearching = false }
        
        let qids = parsedQIDs
        guard !qids.isEmpty else {
            matchResults = []
            return
        }
        
        // Fetch candidates
        var fetchDescriptor = FetchDescriptor<Card>()
        if let deck = selectedDeck {
            let deckID = deck.id
            fetchDescriptor.predicate = #Predicate<Card> { card in
                card.deck?.id == deckID
            }
        }
        
        let allCards = (try? modelContext.fetch(fetchDescriptor)) ?? []
        
        var results: [QIDMatchResult] = []
        
        for qid in qids {
            let matchedCards = allCards.filter { card in
                matches(card: card, qid: qid, source: selectedSource)
            }
            results.append(QIDMatchResult(qid: qid, cards: matchedCards))
        }
        
        self.matchResults = results
    }
    
    private func matches(card: Card, qid: String, source: QBankSource) -> Bool {
        let sourceName: String?
        switch source {
        case .all: sourceName = nil
        case .uworld: sourceName = "uworld"
        case .amboss: sourceName = "amboss"
        }
        return QuestionIDMatcher.matches(qid: qid, source: sourceName, tags: card.tags, front: card.front, back: card.back)
    }

    // MARK: - Aggregates
    var allMatchedCards: [Card] {
        var set = Set<UUID>()
        var list: [Card] = []
        for res in matchResults {
            for card in res.cards {
                if !set.contains(card.id) {
                    set.insert(card.id)
                    list.append(card)
                }
            }
        }
        return list
    }
    
    var totalMatchedCount: Int {
        allMatchedCards.count
    }
    
    var totalSuspendedMatchedCount: Int {
        allMatchedCards.filter { $0.isSuspended }.count
    }
    
    // MARK: - Bulk Actions
    func unsuspendAll() {
        let cards = allMatchedCards
        for card in cards {
            card.isSuspended = false
            card.modifiedAt = Date()
        }
        try? modelContext.save()
        lastActionMessage = "Unsuspended \(cards.count) cards successfully!"
        searchQIDs() // Refresh counts
    }
    
    func suspendAll() {
        let cards = allMatchedCards
        for card in cards {
            card.isSuspended = true
            card.modifiedAt = Date()
        }
        try? modelContext.save()
        lastActionMessage = "Suspended \(cards.count) cards."
        searchQIDs()
    }
    
    func addTagToAll(tag: String) {
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTag.isEmpty else { return }
        
        let cards = allMatchedCards
        for card in cards {
            if !card.tags.contains(cleanTag) {
                card.tags.append(cleanTag)
                card.modifiedAt = Date()
            }
        }
        
        // Also save tag model
        let tagDescriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == cleanTag })
        if let existing = try? modelContext.fetch(tagDescriptor), existing.isEmpty {
            modelContext.insert(Tag(name: cleanTag))
        }
        
        try? modelContext.save()
        lastActionMessage = "Tagged \(cards.count) cards with '#\(cleanTag)'"
    }
    
    func createCramDeck(name: String) -> Deck? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        
        let cramDeck = Deck(
            name: cleanName,
            descriptionText: "Custom cram deck created from QBank QIDs on \(Date().shortDescription)",
            newCardsPerDay: 9999,
            reviewsPerDay: 9999
        )
        modelContext.insert(cramDeck)
        
        let now = Date()
        for card in allMatchedCards {
            // Unsuspend and make due right now for the cram session
            card.isSuspended = false
            card.isBuried = false
            card.dueDate = now
            card.deck = cramDeck
            card.modifiedAt = now
        }
        
        try? modelContext.save()
        lastActionMessage = "Created Cram Deck '\(cleanName)' with \(allMatchedCards.count) cards!"
        return cramDeck
    }
    
    func loadSampleQIDs() {
        rawInput = "1052, 2048, 15302, 1894, 2190"
        searchQIDs()
    }
    
    func clear() {
        rawInput = ""
        matchResults = []
        lastActionMessage = nil
    }
}
