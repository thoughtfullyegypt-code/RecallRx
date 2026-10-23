import Foundation

struct AnkiSchedulingState {
    let state: CardState
    let dueDate: Date
    let interval: Double
    let lastReviewDate: Date?
    let learningStep: Int

    init(card: AnkiImportPackage.ImportedCard, collectionCreation: Date, now: Date) {
        switch card.type {
        case 1: state = .learning
        case 2: state = .review
        case 3: state = .relearning
        default: state = .new
        }
        // Anki stores negative learning intervals in seconds, and review intervals in days.
        interval = card.interval < 0 ? Double(-card.interval) / 86_400 : Double(card.interval)
        let timestampDue = card.queue == 1 || ((card.type == 1 || card.type == 3) && card.due > 1_000_000_000)
        if timestampDue {
            dueDate = Date(timeIntervalSince1970: Double(card.due))
        } else if card.queue == 2 || card.queue == 3 || card.type == 2 || card.type == 3 {
            // Review/day-learning due is a day number relative to col.crt, not an epoch timestamp.
            dueDate = Calendar.current.date(byAdding: .day, value: Int(card.due), to: collectionCreation)
                ?? collectionCreation.addingTimeInterval(Double(card.due) * 86_400)
        } else {
            // A new card's due is its queue position, not a calendar date.
            dueDate = now
        }
        lastReviewDate = card.lastReview ?? (card.type == 2 && interval > 0 ? dueDate.addingTimeInterval(-interval * 86_400) : nil)
        let stepCount = card.type == 3 ? AppConstants.relearningSteps.count : AppConstants.learningSteps.count
        learningStep = max(0, min(stepCount - 1, stepCount - max(1, card.remainingSteps % 1000)))
    }
}
