import Foundation

/// Lossless persistence record for versioned backups.
struct BackupReviewRecord: Codable, Equatable {
    let id: UUID
    let cardID: UUID?
    let rating: Int
    let reviewDate: Date
    let timeTakenMs: Int
    let intervalBefore: Double
    let intervalAfter: Double
    let easeFactorBefore: Double
    let easeFactorAfter: Double
    let cardStateBefore: String
    let cardStateAfter: String

    init(_ model: ReviewLog) {
        id = model.id
        cardID = model.card?.id
        rating = model.rating
        reviewDate = model.reviewDate
        timeTakenMs = model.timeTakenMs
        intervalBefore = model.intervalBefore
        intervalAfter = model.intervalAfter
        easeFactorBefore = model.easeFactorBefore
        easeFactorAfter = model.easeFactorAfter
        cardStateBefore = model.cardStateBefore
        cardStateAfter = model.cardStateAfter
    }
}
