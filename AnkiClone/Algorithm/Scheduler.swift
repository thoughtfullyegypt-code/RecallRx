import Foundation
import SwiftData

final class Scheduler {
    // MARK: - Active Algorithm Configuration
    static var isFSRSEnabled: Bool {
        UserDefaults.standard.bool(forKey: "useFSRS")
    }
    
    static var isFSRSCustomized: Bool {
        UserDefaults.standard.data(forKey: "fsrsCustomWeights") != nil
    }
    
    static var fsrsParameters: FSRSAlgorithm.Parameters {
        let storedRetention = UserDefaults.standard.double(forKey: "fsrsTargetRetention")
        let targetRetention = storedRetention > 0.5 ? storedRetention : 0.90
        var params = FSRSAlgorithm.Parameters(targetRetention: targetRetention)
        
        if let data = UserDefaults.standard.data(forKey: "fsrsCustomWeights"),
           let weights = try? JSONDecoder().decode([Double].self, from: data),
           weights.count == 21 || weights.count == 19 {
            params.w = weights
        }
        
        return params
    }
    
    static func resetFSRSToDefault() {
        UserDefaults.standard.removeObject(forKey: "fsrsCustomWeights")
        UserDefaults.standard.removeObject(forKey: "fsrsLastOptimizedDate")
        UserDefaults.standard.removeObject(forKey: "fsrsOptimizedLossReduction")
        UserDefaults.standard.removeObject(forKey: "fsrsOptimizedSampleCount")
    }
    
    // MARK: - Review Execution
    static func applyReview(card: Card, rating: SM2Algorithm.Rating, timeTakenMs: Int, context: ModelContext) {
        let now = Date.now
        let intervalBefore = card.interval
        let easeFactorBefore = card.easeFactor
        let stateBefore = card.stateRaw
        
        let newInterval: Double
        let newEaseFactor: Double
        let newRepetitions: Int
        let newState: CardState
        let newLearningStep: Int
        
        if isFSRSEnabled {
            let fsrsResult = FSRSAlgorithm.review(card: card, rating: rating, parameters: fsrsParameters)
            newInterval = fsrsResult.newInterval
            newEaseFactor = card.easeFactor // preserved
            newRepetitions = fsrsResult.newReps
            newState = fsrsResult.newState
            newLearningStep = fsrsResult.newLearningStep
            
            card.fsrsStability = fsrsResult.newStability
            card.fsrsDifficulty = fsrsResult.newDifficulty
            card.fsrsReps = fsrsResult.newReps
            card.fsrsLapses = fsrsResult.newLapses
        } else {
            let result = SM2Algorithm.review(card: card, rating: rating)
            newInterval = result.newInterval
            newEaseFactor = result.newEaseFactor
            newRepetitions = result.newRepetitions
            newState = result.newState
            newLearningStep = result.newLearningStep
        }
        
        // Track lapses for review cards rated 'again'
        if card.state == .review && rating == .again {
            card.lapseCount += 1
        }
        
        card.interval = newInterval
        card.easeFactor = newEaseFactor
        card.repetitions = newRepetitions
        card.state = newState
        card.learningStep = newLearningStep
        card.lastReviewDate = now
        if LoadBalancer.isEnabled && newInterval >= 2.0 && newState == .review {
            let deckCards = card.deck?.cards ?? []
            let balancedInterval = LoadBalancer.computeBalancedInterval(targetInterval: newInterval, deckCards: deckCards, referenceDate: now)
            card.dueDate = now.addingTimeInterval(balancedInterval * 86400.0)
        } else {
            card.dueDate = now.addingTimeInterval(newInterval * 86400.0)
        }
        card.modifiedAt = now
        
        let log = ReviewLog(
            card: card,
            rating: rating.rawValue,
            reviewDate: now,
            timeTakenMs: timeTakenMs,
            intervalBefore: intervalBefore,
            intervalAfter: newInterval,
            easeFactorBefore: easeFactorBefore,
            easeFactorAfter: newEaseFactor,
            cardStateBefore: stateBefore,
            cardStateAfter: newState.rawValue
        )
        
        context.insert(log)
        if !card.reviewLogs.contains(where: { $0.id == log.id }) {
            card.reviewLogs.append(log)
        }
        
        try? context.save()
    }
    
    static func nextIntervalDescription(card: Card, rating: SM2Algorithm.Rating) -> String {
        if isFSRSEnabled {
            return FSRSAlgorithm.nextIntervalDescription(card: card, rating: rating, parameters: fsrsParameters)
        } else {
            return SM2Algorithm.nextIntervalDescription(card: card, rating: rating)
        }
    }
    
    // MARK: - Undo Review
    @discardableResult
    static func undoLastReview(card: Card, context: ModelContext) -> Bool {
        guard let lastLog = card.reviewLogs.sorted(by: { $0.reviewDate > $1.reviewDate }).first else {
            return false
        }
        
        card.interval = lastLog.intervalBefore
        card.easeFactor = lastLog.easeFactorBefore
        card.stateRaw = lastLog.cardStateBefore
        
        if lastLog.cardStateBefore == CardState.review.rawValue && lastLog.rating == SM2Algorithm.Rating.again.rawValue {
            card.lapseCount = max(0, card.lapseCount - 1)
        }
        
        if lastLog.rating != SM2Algorithm.Rating.again.rawValue {
            card.repetitions = max(0, card.repetitions - 1)
        }
        
        let previousLogs = card.reviewLogs
            .filter { $0.id != lastLog.id }
            .sorted(by: { $0.reviewDate > $1.reviewDate })
        card.lastReviewDate = previousLogs.first?.reviewDate
        
        // Make the card due immediately for retry
        card.dueDate = .now
        card.modifiedAt = .now
        
        if let index = card.reviewLogs.firstIndex(where: { $0.id == lastLog.id }) {
            card.reviewLogs.remove(at: index)
        }
        context.delete(lastLog)
        
        try? context.save()
        return true
    }
    
    // MARK: - Card Fetching & Filtering
    static func getDueCards(from deck: Deck) -> [Card] {
        let learning = getLearningCards(from: deck)
        let reviews = getReviewCards(from: deck, limit: deck.reviewsPerDay)
        let newCards = getNewCards(from: deck, limit: deck.newCardsPerDay)
        return learning + reviews + newCards
    }
    
    static func getLearningCards(from deck: Deck) -> [Card] {
        getLearningCards(from: deck, dueOnly: true)
    }
    
    static func getLearningCards(from deck: Deck, dueOnly: Bool) -> [Card] {
        deck.cards
            .filter { card in
                guard !card.isSuspended && !card.isBuried else { return false }
                guard card.state == .learning || card.state == .relearning else { return false }
                return dueOnly ? card.dueDate <= Date.now : true
            }
            .sorted { $0.dueDate < $1.dueDate }
    }
    
    static func getReviewCards(from deck: Deck, limit: Int) -> [Card] {
        guard limit > 0 else { return [] }
        let dueReviews = deck.cards
            .filter { card in
                !card.isSuspended && !card.isBuried &&
                card.state == .review &&
                card.dueDate <= Date.now
            }
            .sorted { $0.dueDate < $1.dueDate }
        return Array(dueReviews.prefix(limit))
    }
    
    static func getNewCards(from deck: Deck, limit: Int) -> [Card] {
        guard limit > 0 else { return [] }
        let newCards = deck.cards
            .filter { card in
                !card.isSuspended && !card.isBuried &&
                card.state == .new
            }
            .sorted { $0.createdAt < $1.createdAt }
        return Array(newCards.prefix(limit))
    }
    
    // MARK: - Card Actions
    static func buryCard(_ card: Card) {
        card.isBuried = true
        card.modifiedAt = .now
    }
    
    static func unburyCard(_ card: Card) {
        card.isBuried = false
        card.modifiedAt = .now
    }
    
    static func suspendCard(_ card: Card) {
        card.isSuspended = true
        card.modifiedAt = .now
    }
    
    static func unsuspendCard(_ card: Card) {
        card.isSuspended = false
        card.modifiedAt = .now
    }
    
    static func unburyAllCards(in deck: Deck) {
        for card in deck.cards where card.isBuried {
            card.isBuried = false
            card.modifiedAt = .now
        }
    }
}
