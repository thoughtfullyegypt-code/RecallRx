import Foundation

typealias Rating = SM2Algorithm.Rating

enum AppConstants {
    static let appName = "RecallRx"
    static let defaultNewCardsPerDay = 20
    static let defaultReviewsPerDay = 200
    static let defaultEaseFactor = 2.5
    static let minimumEaseFactor = 1.3
    static let matureInterval = 21 // days
    static let maxInterval = 36500 // days (~100 years)
    static let learningSteps: [Double] = [1, 10] // minutes
    static let relearningSteps: [Double] = [10] // minutes
    static let graduatingInterval: Double = 1 // days
    static let easyInterval: Double = 4 // days
}
