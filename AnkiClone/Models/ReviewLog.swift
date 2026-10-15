import Foundation
import SwiftData

@Model
final class ReviewLog {
    var id: UUID = UUID()
    var card: Card?
    var rating: Int = 0
    var reviewDate: Date = Date()
    var timeTakenMs: Int = 0
    var intervalBefore: Double = 0.0
    var intervalAfter: Double = 0.0
    var easeFactorBefore: Double = 2.5
    var easeFactorAfter: Double = 2.5
    var cardStateBefore: String = "new"
    var cardStateAfter: String = "learning"
    
    var ratingName: String {
        switch rating {
        case 0:
            return "Again"
        case 1:
            return "Hard"
        case 2:
            return "Good"
        case 3:
            return "Easy"
        default:
            return "Unknown"
        }
    }
    
    init(
        id: UUID = UUID(),
        card: Card? = nil,
        rating: Int,
        reviewDate: Date = Date(),
        timeTakenMs: Int = 0,
        intervalBefore: Double = 0.0,
        intervalAfter: Double = 0.0,
        easeFactorBefore: Double = 2.5,
        easeFactorAfter: Double = 2.5,
        cardStateBefore: String = "new",
        cardStateAfter: String = "learning"
    ) {
        self.id = id
        self.card = card
        self.rating = rating
        self.reviewDate = reviewDate
        self.timeTakenMs = timeTakenMs
        self.intervalBefore = intervalBefore
        self.intervalAfter = intervalAfter
        self.easeFactorBefore = easeFactorBefore
        self.easeFactorAfter = easeFactorAfter
        self.cardStateBefore = cardStateBefore
        self.cardStateAfter = cardStateAfter
    }
}
