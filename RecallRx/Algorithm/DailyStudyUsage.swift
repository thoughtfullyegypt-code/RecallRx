import Foundation

/// A study day is the calendar day containing `now`, in the supplied calendar's time zone.
/// Repeated learning steps do not consume another new-card or first-review allowance.
struct DailyStudyUsage {
    let introducedCardIDs: Set<UUID>
    let reviewedCardIDs: Set<UUID>
    let newLimit: Int
    let reviewLimit: Int

    var remainingNew: Int { max(0, newLimit - introducedCardIDs.count) }
    var remainingReviews: Int { max(0, reviewLimit - reviewedCardIDs.count) }
}
