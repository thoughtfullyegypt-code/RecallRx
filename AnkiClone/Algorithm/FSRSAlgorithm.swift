import Foundation
import SwiftUI

struct FSRSAlgorithm {
    // MARK: - FSRS-6 Configuration & Weights (21 Parameters)
    struct Parameters: Sendable {
        var targetRetention: Double = 0.90
        var maximumInterval: Double = 36500.0
        
        // Official open-spaced-repetition FSRS-6 default 21 parameters (Anki 24.04+)
        var w: [Double] = [
            0.40255, 1.18385, 3.173, 15.69105, // 0..3: Initial stabilities for ratings 1, 2, 3, 4
            7.1949, 0.5345,                     // 4..5: Initial difficulty params
            1.4604, 0.0046,                     // 6..7: Difficulty update and mean reversion
            1.5457, 0.1192, 1.0192,             // 8..10: Recall stability multipliers
            1.9395, 0.11, 0.296, 0.2269,        // 11..14: Lapse stability multipliers
            0.2315, 2.9898,                     // 15..16: Hard & Easy bonuses
            0.5165, 0.6621,                     // 17..18: Short-term stability decay
            0.2345679, -0.5                     // 19..20: FSRS-6 power decay curve scaling (factor & decay)
        ]
        
        static let `default` = Parameters()
    }
    
    static let factor: Double = 19.0 / 81.0
    static let decay: Double = -0.5
    
    // MARK: - Review Result
    struct FSRSReviewResult: Sendable {
        let newInterval: Double
        let newStability: Double
        let newDifficulty: Double
        let newReps: Int
        let newLapses: Int
        let newState: CardState
        let newLearningStep: Int
    }
    
    // MARK: - Core Review Execution
    static func review(
        card: Card,
        rating: SM2Algorithm.Rating,
        parameters: Parameters = .default
    ) -> FSRSReviewResult {
        let g = ratingToFSRSGrade(rating)
        let now = Date()
        let lastDate = card.lastReviewDate ?? card.createdAt
        let elapsedDays = max(0.0, now.timeIntervalSince(lastDate) / 86400.0)
        
        // If card is brand new or has no prior stability
        if card.fsrsStability <= 0 || card.state == .new {
            return reviewNewCard(rating: rating, grade: g, parameters: parameters)
        }
        
        let currentS = card.fsrsStability
        let currentD = card.fsrsDifficulty > 0 ? card.fsrsDifficulty : initialDifficulty(grade: 3, parameters: parameters)
        let r = retrievability(stability: currentS, elapsedDays: elapsedDays)
        
        // Update Difficulty with mean reversion
        let nextD = nextDifficulty(currentD: currentD, grade: g, parameters: parameters)
        
        if rating == .again {
            // Lapse
            let nextS = nextForgetStability(currentD: nextD, currentS: currentS, r: r, parameters: parameters)
            let nextInterval = 10.0 / 1440.0 // 10 minutes for relearning step
            
            return FSRSReviewResult(
                newInterval: nextInterval,
                newStability: nextS,
                newDifficulty: nextD,
                newReps: 0,
                newLapses: card.fsrsLapses + 1,
                newState: .relearning,
                newLearningStep: 0
            )
        } else {
            // Recall (Hard, Good, Easy)
            let nextS = nextRecallStability(
                currentD: nextD,
                currentS: currentS,
                r: r,
                grade: g,
                parameters: parameters
            )
            let rawInterval = intervalForTargetRetention(stability: nextS, targetRetention: parameters.targetRetention)
            let nextInterval = min(parameters.maximumInterval, max(1.0, round(rawInterval)))
            
            return FSRSReviewResult(
                newInterval: nextInterval,
                newStability: nextS,
                newDifficulty: nextD,
                newReps: card.fsrsReps + 1,
                newLapses: card.fsrsLapses,
                newState: .review,
                newLearningStep: 0
            )
        }
    }
    
    // MARK: - New Cards Review
    private static func reviewNewCard(
        rating: SM2Algorithm.Rating,
        grade: Int,
        parameters: Parameters
    ) -> FSRSReviewResult {
        let s0 = initialStability(grade: grade, parameters: parameters)
        let d0 = initialDifficulty(grade: grade, parameters: parameters)
        
        switch rating {
        case .again:
            let nextInterval = 1.0 / 1440.0 // 1 minute
            return FSRSReviewResult(
                newInterval: nextInterval,
                newStability: s0,
                newDifficulty: d0,
                newReps: 0,
                newLapses: 1,
                newState: .learning,
                newLearningStep: 0
            )
            
        case .hard:
            let nextInterval = 10.0 / 1440.0 // 10 minutes
            return FSRSReviewResult(
                newInterval: nextInterval,
                newStability: s0,
                newDifficulty: d0,
                newReps: 1,
                newLapses: 0,
                newState: .learning,
                newLearningStep: 1
            )
            
        case .good:
            let rawInterval = intervalForTargetRetention(stability: s0, targetRetention: parameters.targetRetention)
            let nextInterval = max(1.0, round(rawInterval))
            return FSRSReviewResult(
                newInterval: nextInterval,
                newStability: s0,
                newDifficulty: d0,
                newReps: 1,
                newLapses: 0,
                newState: .review,
                newLearningStep: 0
            )
            
        case .easy:
            let rawInterval = intervalForTargetRetention(stability: s0, targetRetention: parameters.targetRetention)
            let nextInterval = max(3.0, round(rawInterval))
            return FSRSReviewResult(
                newInterval: nextInterval,
                newStability: s0,
                newDifficulty: d0,
                newReps: 1,
                newLapses: 0,
                newState: .review,
                newLearningStep: 0
            )
        }
    }
    
    // MARK: - Mathematical Helpers
    static func ratingToFSRSGrade(_ rating: SM2Algorithm.Rating) -> Int {
        switch rating {
        case .again: return 1
        case .hard: return 2
        case .good: return 3
        case .easy: return 4
        }
    }
    
    static func initialStability(grade: Int, parameters: Parameters) -> Double {
        let index = max(0, min(3, grade - 1))
        return max(0.1, parameters.w[index])
    }
    
    static func initialDifficulty(grade: Int, parameters: Parameters) -> Double {
        let g = Double(grade)
        let d0 = parameters.w[4] - exp(parameters.w[5] * (g - 1.0)) + 1.0
        return max(1.0, min(10.0, d0))
    }
    
    static func retrievability(stability: Double, elapsedDays: Double, parameters: Parameters = .default) -> Double {
        guard stability > 0 else { return 0.0 }
        let f = parameters.w.count > 19 ? parameters.w[19] : factor
        let d = parameters.w.count > 20 ? parameters.w[20] : decay
        return pow(1.0 + f * (elapsedDays / stability), d)
    }
    
    static func intervalForTargetRetention(stability: Double, targetRetention: Double, parameters: Parameters = .default) -> Double {
        let r = max(0.70, min(0.99, targetRetention))
        let f = parameters.w.count > 19 ? parameters.w[19] : factor
        let d = parameters.w.count > 20 ? parameters.w[20] : decay
        let interval = (stability / f) * (pow(r, 1.0 / d) - 1.0)
        return max(0.1, interval)
    }
    
    static func nextDifficulty(currentD: Double, grade: Int, parameters: Parameters) -> Double {
        let deltaD = -parameters.w[6] * Double(grade - 3)
        let meanReversion = parameters.w[7] * initialDifficulty(grade: 3, parameters: parameters) + (1.0 - parameters.w[7]) * (currentD + deltaD)
        return max(1.0, min(10.0, meanReversion))
    }
    
    static func nextRecallStability(
        currentD: Double,
        currentS: Double,
        r: Double,
        grade: Int,
        parameters: Parameters
    ) -> Double {
        let bonus: Double
        if grade == 2 {
            bonus = parameters.w[15]
        } else if grade == 4 {
            bonus = parameters.w[16]
        } else {
            bonus = 1.0
        }
        
        let stabilityFactor = 1.0 + exp(parameters.w[8]) * (11.0 - currentD) * pow(currentS, -parameters.w[9]) * (exp(parameters.w[10] * (1.0 - r)) - 1.0) * bonus
        return max(0.1, currentS * stabilityFactor)
    }
    
    static func nextForgetStability(
        currentD: Double,
        currentS: Double,
        r: Double,
        parameters: Parameters
    ) -> Double {
        let forgetStability = parameters.w[11] * pow(currentD, -parameters.w[12]) * (pow(currentS + 1.0, parameters.w[13]) - 1.0) * exp(parameters.w[14] * (1.0 - r))
        return max(0.1, min(currentS, forgetStability))
    }
    
    // MARK: - Interval String Generator
    static func nextIntervalDescription(
        card: Card,
        rating: SM2Algorithm.Rating,
        parameters: Parameters = .default
    ) -> String {
        let result = review(card: card, rating: rating, parameters: parameters)
        return SM2Algorithm.formatInterval(days: result.newInterval, state: result.newState)
    }
}
