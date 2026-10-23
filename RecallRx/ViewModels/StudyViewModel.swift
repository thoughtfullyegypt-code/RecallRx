import Foundation
import SwiftData
import Observation

@Observable
final class StudyViewModel {
    var modelContext: ModelContext
    var deck: Deck
    var currentCard: Card?
    var isShowingAnswer = false
    var studyQueue: [Card] = []

    var cardsStudied = 0
    var correctCount = 0
    var againCount = 0
    var studyStartTime: Date
    var cardStartTime: Date
    var isComplete = false
    var hasRatedCurrentCard = false
    var currentRating: Rating?
    var errorMessage: String?

    var lastReviewedCard: Card?
    var canUndo = false
    var newCount = 0
    var learningCount = 0
    var reviewCount = 0

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var undoSnapshot: StudySessionSnapshot?

    init(
        deck: Deck,
        modelContext: ModelContext,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.deck = deck
        self.modelContext = modelContext
        self.clock = now
        self.calendar = calendar
        self.defaults = defaults
        self.studyStartTime = now()
        self.cardStartTime = now()
        nextCard()
    }

    // MARK: - Queue Construction

    func buildStudyQueue() {
        currentCard = nil
        hasRatedCurrentCard = false
        currentRating = nil
        studyQueue = []
        rebuildAvailableQueue()
        updateCounts()
        isComplete = studyQueue.isEmpty
    }

    private func rebuildAvailableQueue() {
        let now = clock()
        if Scheduler.unburyExpiredCards(in: deck, now: now, calendar: calendar) {
            do { try modelContext.save() } catch { errorMessage = "Could not update buried cards. Try again." }
        }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? .distantFuture
        let due = Scheduler.getDueCards(from: deck, now: now, calendar: calendar)
        let waiting = Scheduler.getLearningCards(from: deck, dueOnly: false, now: now, calendar: calendar)
            .filter { $0.dueDate > now && $0.dueDate < dayEnd }
        let available = due + waiting
        let allowedIDs = Set(available.map(\.id))
        var seen: Set<UUID> = []
        studyQueue = (studyQueue + available).filter { allowedIDs.contains($0.id) && seen.insert($0.id).inserted }
    }

    func nextCard() {
        currentCard = nil
        hasRatedCurrentCard = false
        currentRating = nil
        isShowingAnswer = false
        rebuildAvailableQueue()
        let now = clock()
        let dueLearning = studyQueue.enumerated()
            .filter { ($0.element.state == .learning || $0.element.state == .relearning) && $0.element.dueDate <= now }
            .min { $0.element.dueDate < $1.element.dueDate }?.offset
        let nextIndex = dueLearning ?? studyQueue.firstIndex { $0.state == .new || $0.dueDate <= now }
        if let nextIndex {
            currentCard = studyQueue.remove(at: nextIndex)
            cardStartTime = now
        }
        isComplete = currentCard == nil && studyQueue.isEmpty
        updateCounts()
    }

    var nextLearningDate: Date? {
        studyQueue.filter { $0.state == .learning || $0.state == .relearning }.map(\.dueDate).min()
    }

    var isWaitingForLearning: Bool { currentCard == nil && !isComplete && nextLearningDate != nil }

    /// Called by the visible session timer. Backgrounding never fast-forwards a learning step.
    func refreshDueCards() {
        guard isWaitingForLearning, let nextLearningDate, nextLearningDate <= clock() else { return }
        nextCard()
    }

    // MARK: - Card Navigation & Interaction

    func showAnswer() {
        guard currentCard != nil && !hasRatedCurrentCard else { return }
        isShowingAnswer = true
    }

    @discardableResult
    func rateCard(_ rating: Rating) -> Bool {
        guard let card = currentCard, isShowingAnswer, !hasRatedCurrentCard else { return false }
        let snapshot = StudySessionSnapshot(card: card, queue: studyQueue, cardsStudied: cardsStudied, correctCount: correctCount, againCount: againCount)
        let now = clock()
        let timeTakenMs = max(0, Int(now.timeIntervalSince(cardStartTime) * 1000))
        guard Scheduler.applyReview(card: card, rating: rating, timeTakenMs: timeTakenMs, context: modelContext, now: now, defaults: defaults) else {
            errorMessage = "Your review could not be saved. The card has not advanced. Please try again."
            return false
        }
        undoSnapshot = snapshot
        lastReviewedCard = card
        canUndo = true
        cardsStudied += 1
        if rating == .again { againCount += 1 } else { correctCount += 1 }
        hasRatedCurrentCard = true
        currentRating = rating
        studyQueue.removeAll { $0.id == card.id }
        if defaults.bool(forKey: "autoAdvance") {
            nextCard()
        } else {
            updateCounts()
        }
        return true
    }

    func undoLastReview() {
        guard canUndo, let snapshot = undoSnapshot, let card = lastReviewedCard else { return }
        guard Scheduler.undoLastReview(card: card, context: modelContext, now: clock()) else {
            errorMessage = "The last review could not be undone. Your saved review is unchanged."
            return
        }
        var seen: Set<UUID> = [snapshot.card.id]
        studyQueue = snapshot.queue.filter { seen.insert($0.id).inserted }
        currentCard = snapshot.card
        cardsStudied = snapshot.cardsStudied
        correctCount = snapshot.correctCount
        againCount = snapshot.againCount
        cardStartTime = clock()
        isShowingAnswer = false
        hasRatedCurrentCard = false
        currentRating = nil
        isComplete = false
        lastReviewedCard = nil
        undoSnapshot = nil
        canUndo = false
        updateCounts()
    }

    func skipCard() {
        guard let card = currentCard, !hasRatedCurrentCard else { return }
        let wasBuried = card.isBuried
        let oldExpiry = card.buriedUntil
        let oldModifiedAt = card.modifiedAt
        Scheduler.buryCard(card, now: clock(), calendar: calendar)
        do {
            try modelContext.save()
            nextCard()
        } catch {
            card.isBuried = wasBuried
            card.buriedUntil = oldExpiry
            card.modifiedAt = oldModifiedAt
            errorMessage = "The card could not be buried. Try again."
        }
    }

    func restartIncludingBuriedCards() {
        let previous = deck.cards.filter(\.isBuried).map { ($0, $0.buriedUntil, $0.modifiedAt) }
        Scheduler.unburyAllCards(in: deck, now: clock())
        do {
            try modelContext.save()
            buildStudyQueue()
            nextCard()
        } catch {
            for (card, expiry, modified) in previous {
                card.isBuried = true
                card.buriedUntil = expiry
                card.modifiedAt = modified
            }
            errorMessage = "The buried cards could not be restored. Try again."
        }
    }

    // MARK: - Statistics & Metadata

    var elapsedTime: TimeInterval { max(0, clock().timeIntervalSince(studyStartTime)) }

    var intervalStrings: [Rating: String] {
        guard let card = currentCard, !hasRatedCurrentCard else { return [:] }
        return Dictionary(uniqueKeysWithValues: Rating.allCases.map {
            ($0, Scheduler.nextIntervalDescription(card: card, rating: $0, now: clock(), defaults: defaults))
        })
    }

    func updateCounts() {
        var remaining = studyQueue
        if let currentCard, !hasRatedCurrentCard { remaining.append(currentCard) }
        newCount = remaining.filter { $0.state == .new }.count
        learningCount = remaining.filter { $0.state == .learning || $0.state == .relearning }.count
        reviewCount = remaining.filter { $0.state == .review }.count
    }
}

// MARK: - Scheduler Interoperability Extensions

extension Scheduler {
    static func getDueCards(for deck: Deck) -> [Card] { getDueCards(from: deck) }
    static func getLearningCards(for deck: Deck) -> [Card] { getLearningCards(from: deck) }
    static func getReviewCards(for deck: Deck, limit: Int? = nil) -> [Card] { getReviewCards(from: deck, limit: limit ?? deck.reviewsPerDay) }
    static func getNewCards(for deck: Deck, limit: Int? = nil) -> [Card] { getNewCards(from: deck, limit: limit ?? deck.newCardsPerDay) }
}
