import Foundation
import SwiftData
import Observation

@Observable
final class StudyViewModel {
    var modelContext: ModelContext
    var deck: Deck
    var currentCard: Card?
    var isShowingAnswer: Bool = false
    var studyQueue: [Card] = []
    
    var cardsStudied: Int = 0
    var correctCount: Int = 0
    var againCount: Int = 0
    
    var studyStartTime: Date
    var cardStartTime: Date
    var isComplete: Bool = false
    
    var lastReviewedCard: Card?
    var canUndo: Bool = false
    
    var newCount: Int = 0
    var learningCount: Int = 0
    var reviewCount: Int = 0
    
    init(deck: Deck, modelContext: ModelContext) {
        self.deck = deck
        self.modelContext = modelContext
        self.studyStartTime = .now
        self.cardStartTime = .now
        buildStudyQueue()
        nextCard()
    }
    
    // MARK: - Queue Construction
    
    func buildStudyQueue() {
        studyQueue = Scheduler.getDueCards(from: deck)
        updateCounts()
        isComplete = studyQueue.isEmpty && currentCard == nil
    }
    
    // MARK: - Card Navigation & Interaction
    
    func showAnswer() {
        isShowingAnswer = true
    }
    
    func nextCard() {
        isShowingAnswer = false
        if studyQueue.isEmpty {
            currentCard = nil
            isComplete = true
            updateCounts()
            return
        }
        currentCard = studyQueue.removeFirst()
        cardStartTime = .now
        isComplete = false
        updateCounts()
    }
    
    func rateCard(_ rating: SM2Algorithm.Rating) {
        guard let card = currentCard else { return }
        
        let timeTakenMs = Int(Date.now.timeIntervalSince(cardStartTime) * 1000)
        
        Scheduler.applyReview(card: card, rating: rating, timeTakenMs: timeTakenMs, context: modelContext)
        
        lastReviewedCard = card
        canUndo = true
        cardsStudied += 1
        
        if rating == .again {
            againCount += 1
            // Re-insert into queue for same-session practice if still in learning/relearning
            if card.state == .learning || card.state == .relearning {
                let insertIndex = min(studyQueue.count, 3)
                studyQueue.insert(card, at: insertIndex)
            }
        } else {
            correctCount += 1
            // Keep learning card in current session if another learning step is due within 10 minutes
            if (card.state == .learning || card.state == .relearning) && card.dueDate <= Date.now.addingTimeInterval(600) {
                studyQueue.append(card)
            }
        }
        
        nextCard()
    }
    
    func undoLastReview() {
        guard canUndo, let card = lastReviewedCard else { return }
        
        let undone = Scheduler.undoLastReview(card: card, context: modelContext)
        if undone {
            if let current = currentCard {
                studyQueue.insert(current, at: 0)
            }
            currentCard = card
            cardStartTime = .now
            isShowingAnswer = false
            isComplete = false
            
            if cardsStudied > 0 {
                cardsStudied -= 1
            }
            lastReviewedCard = nil
            canUndo = false
            updateCounts()
        }
    }
    
    func skipCard() {
        guard let card = currentCard else { return }
        Scheduler.buryCard(card)
        try? modelContext.save()
        nextCard()
    }
    
    // MARK: - Statistics & Metadata
    
    var elapsedTime: TimeInterval {
        Date.now.timeIntervalSince(studyStartTime)
    }
    
    var intervalStrings: [SM2Algorithm.Rating: String] {
        guard let card = currentCard else { return [:] }
        var result: [SM2Algorithm.Rating: String] = [:]
        for rating in SM2Algorithm.Rating.allCases {
            result[rating] = Scheduler.nextIntervalDescription(card: card, rating: rating)
        }
        return result
    }
    
    func updateCounts() {
        var allRemaining = studyQueue
        if let current = currentCard {
            allRemaining.append(current)
        }
        newCount = allRemaining.filter { $0.state == .new }.count
        learningCount = allRemaining.filter { $0.state == .learning || $0.state == .relearning }.count
        reviewCount = allRemaining.filter { $0.state == .review }.count
    }
}

// MARK: - Scheduler Interoperability Extensions

extension Scheduler {
    static func getDueCards(for deck: Deck) -> [Card] {
        getDueCards(from: deck)
    }
    
    static func getLearningCards(for deck: Deck) -> [Card] {
        getLearningCards(from: deck)
    }
    
    static func getReviewCards(for deck: Deck, limit: Int? = nil) -> [Card] {
        getReviewCards(from: deck, limit: limit ?? deck.reviewsPerDay)
    }
    
    static func getNewCards(for deck: Deck, limit: Int? = nil) -> [Card] {
        getNewCards(from: deck, limit: limit ?? deck.newCardsPerDay)
    }
}

