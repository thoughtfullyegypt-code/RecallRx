import Foundation
import SwiftUI

struct SM2Algorithm {
    // MARK: - Rating Enum
    enum Rating: Int, CaseIterable, Identifiable, Sendable {
        case again = 0
        case hard = 1
        case good = 2
        case easy = 3
        
        var id: Int { rawValue }
        
        var name: String {
            switch self {
            case .again: return "Again"
            case .hard: return "Hard"
            case .good: return "Good"
            case .easy: return "Easy"
            }
        }
        
        var color: Color {
            switch self {
            case .again: return .red
            case .hard: return .orange
            case .good: return .green
            case .easy: return .blue
            }
        }
    }
    
    // MARK: - Review Result
    struct ReviewResult: Sendable, Equatable {
        let newInterval: Double
        let newEaseFactor: Double
        let newRepetitions: Int
        let newState: CardState
        let newLearningStep: Int
    }
    
    // MARK: - Parameters & Defaults
    // Learning steps in minutes
    static let learningSteps: [Double] = [1, 10]
    static let relearningSteps: [Double] = [10]
    static let graduatingInterval: Double = 1.0 // days
    static let easyInterval: Double = 4.0 // days
    static let minimumEaseFactor: Double = 1.3
    static let easyBonus: Double = 1.3
    static let intervalModifier: Double = 1.0
    static let hardIntervalMultiplier: Double = 1.2
    static let newInterval: Double = 0.0 // multiplier for lapsed cards
    static let maximumInterval: Double = 36500.0 // 100 years
    
    // MARK: - Core Review Logic
    static func review(
        card: Card,
        rating: Rating,
        parameters: SM2SchedulingParameters = .load()
    ) -> ReviewResult {
        switch card.state {
        case .new:
            return reviewNewCard(card: card, rating: rating, parameters: parameters)
        case .learning:
            return reviewLearningCard(card: card, rating: rating, parameters: parameters)
        case .review:
            return reviewReviewCard(card: card, rating: rating)
        case .relearning:
            return reviewRelearningCard(card: card, rating: rating, parameters: parameters)
        }
    }
    
    // MARK: - New Cards
    private static func reviewNewCard(
        card: Card,
        rating: Rating,
        parameters: SM2SchedulingParameters
    ) -> ReviewResult {
        let learningSteps = parameters.learningStepsMinutes
        let graduatingInterval = parameters.graduatingInterval
        let easyInterval = parameters.easyInterval
        switch rating {
        case .again:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.2)
            let step = 0
            let intervalDays = learningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: 0,
                newState: .learning,
                newLearningStep: step
            )
            
        case .hard:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.15)
            let step = 0
            let intervalDays = learningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: 0,
                newState: .learning,
                newLearningStep: step
            )
            
        case .good:
            if learningSteps.count > 1 {
                let step = 1
                let intervalDays = learningSteps[step] / 1440.0
                return ReviewResult(
                    newInterval: intervalDays,
                    newEaseFactor: card.easeFactor,
                    newRepetitions: 0,
                    newState: .learning,
                    newLearningStep: step
                )
            } else {
                return ReviewResult(
                    newInterval: graduatingInterval,
                    newEaseFactor: card.easeFactor,
                    newRepetitions: 1,
                    newState: .review,
                    newLearningStep: 0
                )
            }
            
        case .easy:
            return ReviewResult(
                newInterval: easyInterval,
                newEaseFactor: card.easeFactor,
                newRepetitions: 1,
                newState: .review,
                newLearningStep: 0
            )
        }
    }
    
    // MARK: - Learning Cards
    private static func reviewLearningCard(
        card: Card,
        rating: Rating,
        parameters: SM2SchedulingParameters
    ) -> ReviewResult {
        let learningSteps = parameters.learningStepsMinutes
        let graduatingInterval = parameters.graduatingInterval
        let easyInterval = parameters.easyInterval
        let currentStep = max(0, min(card.learningStep, learningSteps.count - 1))
        
        switch rating {
        case .again:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.2)
            let step = 0
            let intervalDays = learningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: 0,
                newState: .learning,
                newLearningStep: step
            )
            
        case .hard:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.15)
            let step = currentStep
            let intervalDays = learningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: card.repetitions,
                newState: .learning,
                newLearningStep: step
            )
            
        case .good:
            let nextStep = currentStep + 1
            if nextStep < learningSteps.count {
                let intervalDays = learningSteps[nextStep] / 1440.0
                return ReviewResult(
                    newInterval: intervalDays,
                    newEaseFactor: card.easeFactor,
                    newRepetitions: card.repetitions,
                    newState: .learning,
                    newLearningStep: nextStep
                )
            } else {
                return ReviewResult(
                    newInterval: graduatingInterval,
                    newEaseFactor: card.easeFactor,
                    newRepetitions: max(1, card.repetitions + 1),
                    newState: .review,
                    newLearningStep: 0
                )
            }
            
        case .easy:
            return ReviewResult(
                newInterval: easyInterval,
                newEaseFactor: card.easeFactor,
                newRepetitions: max(1, card.repetitions + 1),
                newState: .review,
                newLearningStep: 0
            )
        }
    }
    
    // MARK: - Relearning Cards
    private static func reviewRelearningCard(
        card: Card,
        rating: Rating,
        parameters: SM2SchedulingParameters
    ) -> ReviewResult {
        let graduatingInterval = parameters.graduatingInterval
        let easyInterval = parameters.easyInterval
        let currentStep = max(0, min(card.learningStep, relearningSteps.count - 1))
        
        switch rating {
        case .again:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.2)
            let step = 0
            let intervalDays = relearningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: 0,
                newState: .relearning,
                newLearningStep: step
            )
            
        case .hard:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.15)
            let step = currentStep
            let intervalDays = relearningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: card.repetitions,
                newState: .relearning,
                newLearningStep: step
            )
            
        case .good:
            let nextStep = currentStep + 1
            if nextStep < relearningSteps.count {
                let intervalDays = relearningSteps[nextStep] / 1440.0
                return ReviewResult(
                    newInterval: intervalDays,
                    newEaseFactor: card.easeFactor,
                    newRepetitions: card.repetitions,
                    newState: .relearning,
                    newLearningStep: nextStep
                )
            } else {
                return ReviewResult(
                    newInterval: graduatingInterval,
                    newEaseFactor: card.easeFactor,
                    newRepetitions: 1,
                    newState: .review,
                    newLearningStep: 0
                )
            }
            
        case .easy:
            return ReviewResult(
                newInterval: easyInterval,
                newEaseFactor: card.easeFactor,
                newRepetitions: 1,
                newState: .review,
                newLearningStep: 0
            )
        }
    }
    
    // MARK: - Review Cards
    private static func reviewReviewCard(card: Card, rating: Rating) -> ReviewResult {
        let currentInterval = max(1.0, card.interval)
        
        switch rating {
        case .again:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.2)
            let step = 0
            let intervalDays = relearningSteps[step] / 1440.0
            return ReviewResult(
                newInterval: intervalDays,
                newEaseFactor: ease,
                newRepetitions: 0,
                newState: .relearning,
                newLearningStep: step
            )
            
        case .hard:
            let ease = max(minimumEaseFactor, card.easeFactor - 0.15)
            let rawInterval = currentInterval * hardIntervalMultiplier * intervalModifier
            let nextInterval = min(maximumInterval, max(1.0, rawInterval))
            return ReviewResult(
                newInterval: nextInterval,
                newEaseFactor: ease,
                newRepetitions: card.repetitions + 1,
                newState: .review,
                newLearningStep: 0
            )
            
        case .good:
            let rawInterval = currentInterval * card.easeFactor * intervalModifier
            let nextInterval = min(maximumInterval, max(currentInterval + 1.0, rawInterval))
            return ReviewResult(
                newInterval: nextInterval,
                newEaseFactor: card.easeFactor,
                newRepetitions: card.repetitions + 1,
                newState: .review,
                newLearningStep: 0
            )
            
        case .easy:
            let ease = card.easeFactor + 0.15
            let rawInterval = currentInterval * card.easeFactor * easyBonus * intervalModifier
            let nextInterval = min(maximumInterval, max(currentInterval + 1.0, rawInterval))
            return ReviewResult(
                newInterval: nextInterval,
                newEaseFactor: ease,
                newRepetitions: card.repetitions + 1,
                newState: .review,
                newLearningStep: 0
            )
        }
    }
    
    // MARK: - Description Formatter
    static func nextIntervalDescription(
        card: Card,
        rating: Rating,
        parameters: SM2SchedulingParameters = .load()
    ) -> String {
        let result = review(card: card, rating: rating, parameters: parameters)
        return formatInterval(days: result.newInterval, state: result.newState)
    }
    
    static func formatInterval(days: Double, state: CardState? = nil) -> String {
        let minutes = days * 1440.0
        
        if state == .learning || state == .relearning || days < 1.0 {
            if minutes < 0.95 {
                return "<1m"
            } else if minutes < 59.5 {
                return "\(Int(round(minutes)))m"
            } else if minutes < 1410.0 {
                let hours = max(1, Int(round(minutes / 60.0)))
                return "\(hours)h"
            }
        }
        
        if days < 30.0 {
            let d = max(1, Int(round(days)))
            return "\(d)d"
        } else if days < 365.0 {
            let months = days / 30.0
            if months < 10.0 {
                let rounded = (months * 10.0).rounded() / 10.0
                return rounded.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(rounded))mo" : String(format: "%.1fmo", rounded)
            } else {
                return "\(Int(round(months)))mo"
            }
        } else {
            let years = days / 365.0
            let rounded = (years * 10.0).rounded() / 10.0
            return rounded.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(rounded))y" : String(format: "%.1fy", rounded)
        }
    }
}
