import Foundation
import SwiftUI

struct FSRSAlgorithm {
    // MARK: - FSRS-6 Configuration & Weights (21 Parameters)
    struct Parameters: Sendable {
        var targetRetention: Double = 0.90
        var maximumInterval: Double = 36500.0

        /// Official FSRS-6 defaults (open-spaced-repetition, 21 parameters).
        /// w[19] is the short-term stability power. w[20] is a positive decay.
        /// The forgetting-curve factor is derived from w[20] so R(t = S) = 90%.
        var w: [Double] = [
            0.212, 1.2931, 2.3065, 8.2956,
            6.4133, 0.8334,
            3.0194, 0.001,
            1.8722, 0.1666, 0.796,
            1.4835, 0.0614, 0.2629, 1.6483,
            0.6014, 1.8729,
            0.5425, 0.0912,
            0.0658, 0.1542
        ]

        static let `default` = Parameters()
    }

    /// Anki-style learning steps, in minutes. Good on a new card advances, it does not graduate.
    static let learningStepsMinutes: [Double] = [1, 10]
    static let relearningStepsMinutes: [Double] = [10]

    struct FSRSReviewResult: Sendable {
        let newInterval: Double
        let newStability: Double
        let newDifficulty: Double
        let newReps: Int
        let newLapses: Int
        let newState: CardState
        let newLearningStep: Int
    }

    struct Curve: Sendable {
        let decay: Double
        let factor: Double
        /// True when w[20] was stored as a negative FSRS-5 decay and w[19] is not the FSRS-6 power term.
        let legacyNegativeDecay: Bool
    }

    // MARK: - Review

    static func review(
        card: Card,
        rating: SM2Algorithm.Rating,
        parameters: Parameters = .default,
        now: Date = Date()
    ) -> FSRSReviewResult {
        let grade = ratingToFSRSGrade(rating)
        let inferredLastReview = card.state == .review && card.interval > 0
            ? card.dueDate.addingTimeInterval(-card.interval * 86400) : card.createdAt
        let lastDate = card.lastReviewDate ?? inferredLastReview
        let elapsedDays = max(0.0, now.timeIntervalSince(lastDate) / 86400.0)

        if card.state == .new {
            return reviewNewCard(rating: rating, grade: grade, parameters: parameters)
        }

        // SM-2 imports can have real review progression without FSRS fields. Use
        // their existing interval as a conservative conversion seed, rather than
        // treating a mature card as a new introduction or inventing old reviews.
        let currentS = card.fsrsStability > 0
            ? max(0.001, card.fsrsStability) : min(36500, max(1, card.interval))
        let currentD = card.fsrsDifficulty > 0 ? card.fsrsDifficulty : initialDifficulty(grade: 3, parameters: parameters)
        let sameDay = elapsedDays < 1.0

        if card.state == .learning || card.state == .relearning || sameDay {
            return reviewShortTerm(
                card: card,
                rating: rating,
                grade: grade,
                currentS: currentS,
                currentD: currentD,
                parameters: parameters
            )
        }

        let r = retrievability(stability: currentS, elapsedDays: elapsedDays, parameters: parameters)
        let nextD = nextDifficulty(currentD: currentD, grade: grade, parameters: parameters)

        if rating == .again {
            let nextS = nextForgetStability(currentD: nextD, currentS: currentS, r: r, parameters: parameters)
            return FSRSReviewResult(
                newInterval: relearningStepsMinutes[0] / 1440.0,
                newStability: nextS,
                newDifficulty: nextD,
                newReps: previousRepetitions(for: card),
                newLapses: previousLapses(for: card) + 1,
                newState: .relearning,
                newLearningStep: 0
            )
        }

        let nextS = nextRecallStability(
            currentD: nextD,
            currentS: currentS,
            r: r,
            grade: grade,
            parameters: parameters
        )
        return FSRSReviewResult(
            newInterval: scheduledInterval(stability: nextS, parameters: parameters),
            newStability: nextS,
            newDifficulty: nextD,
            newReps: previousRepetitions(for: card) + 1,
            newLapses: previousLapses(for: card),
            newState: .review,
            newLearningStep: 0
        )
    }

    private static func reviewNewCard(
        rating: SM2Algorithm.Rating,
        grade: Int,
        parameters: Parameters
    ) -> FSRSReviewResult {
        let s0 = initialStability(grade: grade, parameters: parameters)
        let d0 = initialDifficulty(grade: grade, parameters: parameters)

        switch rating {
        case .again:
            return FSRSReviewResult(
                newInterval: learningStepsMinutes[0] / 1440.0,
                newStability: s0,
                newDifficulty: d0,
                newReps: 0,
                newLapses: 0,
                newState: .learning,
                newLearningStep: 0
            )
        case .hard:
            return FSRSReviewResult(
                newInterval: 6.0 / 1440.0,
                newStability: s0,
                newDifficulty: d0,
                newReps: 0,
                newLapses: 0,
                newState: .learning,
                newLearningStep: 0
            )
        case .good:
            let step = min(1, learningStepsMinutes.count - 1)
            return FSRSReviewResult(
                newInterval: learningStepsMinutes[step] / 1440.0,
                newStability: s0,
                newDifficulty: d0,
                newReps: 0,
                newLapses: 0,
                newState: .learning,
                newLearningStep: step
            )
        case .easy:
            return FSRSReviewResult(
                newInterval: scheduledInterval(stability: s0, parameters: parameters),
                newStability: s0,
                newDifficulty: d0,
                newReps: 1,
                newLapses: 0,
                newState: .review,
                newLearningStep: 0
            )
        }
    }

    private static func reviewShortTerm(
        card: Card,
        rating: SM2Algorithm.Rating,
        grade: Int,
        currentS: Double,
        currentD: Double,
        parameters: Parameters
    ) -> FSRSReviewResult {
        let nextD = nextDifficulty(currentD: currentD, grade: grade, parameters: parameters)
        let nextS = nextShortTermStability(currentS: currentS, grade: grade, parameters: parameters)
        let steps = card.state == .relearning ? relearningStepsMinutes : learningStepsMinutes
        let lastStep = max(0, steps.count - 1)

        switch rating {
        case .again:
            return FSRSReviewResult(
                newInterval: steps[0] / 1440.0,
                newStability: nextS,
                newDifficulty: nextD,
                newReps: previousRepetitions(for: card),
                newLapses: card.state == .review ? previousLapses(for: card) + 1 : previousLapses(for: card),
                newState: card.state == .review ? .relearning : card.state,
                newLearningStep: 0
            )
        case .hard:
            let step = min(card.learningStep, lastStep)
            return FSRSReviewResult(
                newInterval: steps[step] / 1440.0,
                newStability: nextS,
                newDifficulty: nextD,
                newReps: previousRepetitions(for: card),
                newLapses: previousLapses(for: card),
                newState: card.state == .review ? .review : card.state,
                newLearningStep: step
            )
        case .good, .easy:
            let graduating = card.learningStep >= lastStep || rating == .easy || card.state == .review
            if graduating {
                return FSRSReviewResult(
                    newInterval: scheduledInterval(stability: nextS, parameters: parameters),
                    newStability: nextS,
                    newDifficulty: nextD,
                    newReps: previousRepetitions(for: card) + 1,
                    newLapses: previousLapses(for: card),
                    newState: .review,
                    newLearningStep: 0
                )
            }
            let nextStep = min(lastStep, card.learningStep + 1)
            return FSRSReviewResult(
                newInterval: steps[nextStep] / 1440.0,
                newStability: nextS,
                newDifficulty: nextD,
                newReps: previousRepetitions(for: card),
                newLapses: previousLapses(for: card),
                newState: card.state,
                newLearningStep: nextStep
            )
        }
    }

    private static func previousRepetitions(for card: Card) -> Int {
        card.fsrsStability > 0 ? card.fsrsReps : max(card.fsrsReps, card.repetitions)
    }

    private static func previousLapses(for card: Card) -> Int {
        card.fsrsStability > 0 ? card.fsrsLapses : max(card.fsrsLapses, card.lapseCount)
    }

    // MARK: - Math

    static func ratingToFSRSGrade(_ rating: SM2Algorithm.Rating) -> Int {
        switch rating {
        case .again: return 1
        case .hard: return 2
        case .good: return 3
        case .easy: return 4
        }
    }

    static func curve(parameters: Parameters) -> Curve {
        var decay = parameters.w.count > 20 ? parameters.w[20] : 0.1542
        let legacy = decay < 0
        if legacy { decay = -decay }
        if decay < 0.1 || decay > 0.8 { decay = 0.1542 }
        let factor = pow(0.9, -1.0 / decay) - 1.0
        return Curve(decay: decay, factor: factor, legacyNegativeDecay: legacy)
    }

    static func initialStability(grade: Int, parameters: Parameters) -> Double {
        let index = max(0, min(3, grade - 1))
        guard parameters.w.indices.contains(index) else { return 0.1 }
        return max(0.001, parameters.w[index])
    }

    static func initialDifficulty(grade: Int, parameters: Parameters) -> Double {
        guard parameters.w.count > 5 else { return 5 }
        let g = Double(grade)
        let d0 = parameters.w[4] - exp(parameters.w[5] * (g - 1.0)) + 1.0
        return min(10.0, max(1.0, d0))
    }

    static func retrievability(stability: Double, elapsedDays: Double, parameters: Parameters = .default) -> Double {
        guard stability > 0 else { return 0 }
        let curve = curve(parameters: parameters)
        let r = pow(1.0 + curve.factor * (elapsedDays / stability), -curve.decay)
        if r.isNaN { return 0 }
        return min(1.0, max(0.0, r))
    }

    static func intervalForTargetRetention(stability: Double, targetRetention: Double, parameters: Parameters = .default) -> Double {
        let curve = curve(parameters: parameters)
        let r = min(0.99, max(0.70, targetRetention))
        let interval = (stability / curve.factor) * (pow(r, -1.0 / curve.decay) - 1.0)
        if interval.isNaN { return 1 }
        return max(0.1, interval)
    }

    static func scheduledInterval(stability: Double, parameters: Parameters) -> Double {
        let raw = intervalForTargetRetention(stability: stability, targetRetention: parameters.targetRetention, parameters: parameters)
        return min(parameters.maximumInterval, max(1.0, round(raw)))
    }

    static func nextDifficulty(currentD: Double, grade: Int, parameters: Parameters) -> Double {
        guard parameters.w.count > 7 else { return currentD }
        let delta = -parameters.w[6] * Double(grade - 3)
        let damped = currentD + delta * (10.0 - currentD) / 9.0
        let anchor = initialDifficulty(grade: 4, parameters: parameters)
        let reverted = parameters.w[7] * anchor + (1.0 - parameters.w[7]) * damped
        return min(10.0, max(1.0, reverted))
    }

    static func nextRecallStability(
        currentD: Double,
        currentS: Double,
        r: Double,
        grade: Int,
        parameters: Parameters
    ) -> Double {
        guard parameters.w.count > 16 else { return currentS }
        let hardPenalty = grade == 2 ? parameters.w[15] : 1.0
        let easyBonus = grade == 4 ? parameters.w[16] : 1.0
        let factor = 1.0
            + exp(parameters.w[8])
            * (11.0 - currentD)
            * pow(currentS, -parameters.w[9])
            * (exp(parameters.w[10] * (1.0 - r)) - 1.0)
            * hardPenalty
            * easyBonus
        return min(36500.0, max(0.001, currentS * factor))
    }

    static func nextForgetStability(
        currentD: Double,
        currentS: Double,
        r: Double,
        parameters: Parameters
    ) -> Double {
        guard parameters.w.count > 14 else { return max(0.001, currentS * 0.5) }
        let raw = parameters.w[11]
            * pow(currentD, -parameters.w[12])
            * (pow(currentS + 1.0, parameters.w[13]) - 1.0)
            * exp(parameters.w[14] * (1.0 - r))
        let cap: Double
        if parameters.w.count > 18 {
            cap = currentS / exp(parameters.w[17] * parameters.w[18])
        } else {
            cap = currentS
        }
        let bounded = min(raw, cap)
        return min(36500.0, max(0.001, bounded))
    }

    /// Same-day stability. Hard, Good, and Easy cannot decrease it. Again can.
    static func nextShortTermStability(currentS: Double, grade: Int, parameters: Parameters) -> Double {
        guard parameters.w.count > 18 else { return currentS }
        let curve = curve(parameters: parameters)
        let exponent = parameters.w[17] * (Double(grade) - 3.0 + parameters.w[18])
        let sinc: Double
        if curve.legacyNegativeDecay || parameters.w.count <= 19 {
            sinc = exp(exponent)
        } else {
            sinc = pow(max(currentS, 0.001), -parameters.w[19]) * exp(exponent)
        }
        let held = grade >= 2 ? max(sinc, 1.0) : sinc
        return min(36500.0, max(0.001, currentS * held))
    }

    static func nextIntervalDescription(
        card: Card,
        rating: SM2Algorithm.Rating,
        parameters: Parameters = .default,
        now: Date = .now
    ) -> String {
        let result = review(card: card, rating: rating, parameters: parameters, now: now)
        return SM2Algorithm.formatInterval(days: result.newInterval, state: result.newState)
    }
}
