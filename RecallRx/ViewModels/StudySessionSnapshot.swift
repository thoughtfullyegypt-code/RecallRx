import Foundation

/// UI/session state captured before grading; card scheduling is restored by Scheduler.
struct StudySessionSnapshot {
    let card: Card
    let queue: [Card]
    let cardsStudied: Int
    let correctCount: Int
    let againCount: Int
}
