import Foundation
import SwiftData

/// On-Device FSRS-5 Parameter Optimization Engine
/// Fits custom memory stability and difficulty parameters to the student's individual retention history.
final class FSRSOptimizer {
    
    // MARK: - Optimization Result
    struct OptimizationResult: Sendable, Codable {
        let weights: [Double]
        let initialLoss: Double
        let optimizedLoss: Double
        let sampleCount: Int
        let durationMs: Int
        let timestamp: Date
        
        var lossReductionPercent: Double {
            guard initialLoss > 0 else { return 0 }
            let reduction = (initialLoss - optimizedLoss) / initialLoss * 100.0
            return max(0.0, reduction)
        }
        
        var formattedReduction: String {
            String(format: "%.1f%%", lossReductionPercent)
        }
    }
    
    // MARK: - Review Sample for Training
    struct ReviewSequence: Sendable {
        let cardId: UUID
        let steps: [ReviewStep]
    }
    
    struct ReviewStep: Sendable {
        let elapsedDays: Double
        let grade: Int        // 1: Again, 2: Hard, 3: Good, 4: Easy
        let recalled: Double  // 1.0 if grade >= 2, 0.0 if grade == 1
    }
    
    // MARK: - Optimization Guard & Error
    static let minimumRequiredReviews = 1000
    
    enum FSRSOptimizationError: LocalizedError {
        case insufficientReviews(current: Int, required: Int)
        case noData
        
        var errorDescription: String? {
            switch self {
            case .insufficientReviews(let current, let required):
                return "FSRS weight personalization requires at least \(required) reviews for statistical validity (currently: \(current) / \(required)). Optimizing with fewer reviews risks severe overfitting and inaccurate scheduling."
            case .noData:
                return "No review history available to optimize."
            }
        }
    }
    
    static func getReviewCount(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<ReviewLog>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }
    
    // MARK: - Main Optimization Function
    static func optimize(context: ModelContext, allowBypassMinReviews: Bool = false) async throws -> OptimizationResult {
        let startTime = DispatchTime.now()
        
        // 1. Fetch all ReviewLogs from SwiftData
        let descriptor = FetchDescriptor<ReviewLog>(
            sortBy: [SortDescriptor(\.reviewDate, order: .forward)]
        )
        let logs = (try? context.fetch(descriptor)) ?? []
        
        // Enforce the 1,000 review minimum unless explicitly bypassed in testing
        if !allowBypassMinReviews && logs.count < minimumRequiredReviews {
            throw FSRSOptimizationError.insufficientReviews(current: logs.count, required: minimumRequiredReviews)
        }
        
        // 2. Build review sequences per card
        var sequences = buildSequences(from: logs)
        var trainedOnSyntheticData = false

        // Synthetic reviews are only for the in-app test bypass. Never save them as the user's memory.
        if allowBypassMinReviews && sequences.flatMap({ $0.steps }).count < 10 {
            sequences.append(contentsOf: generateCalibratedSyntheticSequences())
            trainedOnSyntheticData = true
        }
        
        let totalSamples = sequences.reduce(0) { $0 + max(0, $1.steps.count - 1) }
        guard totalSamples > 0 else {
            throw FSRSOptimizationError.noData
        }
        
        // 3. Run optimization on background thread
        let defaultWeights = FSRSAlgorithm.Parameters.default.w
        let initialLoss = evaluateLoss(weights: defaultWeights, sequences: sequences)
        
        let optimizedWeights = await Task.detached(priority: .userInitiated) {
            return runGradientDescent(initialWeights: defaultWeights, sequences: sequences)
        }.value
        
        let optimizedLoss = evaluateLoss(weights: optimizedWeights, sequences: sequences)
        let endTime = DispatchTime.now()
        let durationMs = Int((endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)
        
        let result = OptimizationResult(
            weights: optimizedWeights,
            initialLoss: initialLoss,
            optimizedLoss: optimizedLoss,
            sampleCount: totalSamples,
            durationMs: durationMs,
            timestamp: Date()
        )
        
        if !trainedOnSyntheticData {
            saveOptimizationResult(result)
        }
        
        return result
    }
    
    // MARK: - Build Sequences
    private static func buildSequences(from logs: [ReviewLog]) -> [ReviewSequence] {
        var cardLogs: [UUID: [ReviewLog]] = [:]
        for log in logs {
            guard let card = log.card else { continue }
            cardLogs[card.id, default: []].append(log)
        }
        
        var sequences: [ReviewSequence] = []
        for (cardId, logsForCard) in cardLogs {
            let sorted = logsForCard.sorted(by: { $0.reviewDate < $1.reviewDate })
            var steps: [ReviewStep] = []
            var lastDate: Date? = nil
            
            for log in sorted {
                let elapsed: Double
                if let last = lastDate {
                    elapsed = max(0.01, log.reviewDate.timeIntervalSince(last) / 86400.0)
                } else {
                    elapsed = 0.0
                }
                lastDate = log.reviewDate
                
                let grade = max(1, min(4, log.rating + 1))
                let recalled = (grade >= 2) ? 1.0 : 0.0
                steps.append(ReviewStep(elapsedDays: elapsed, grade: grade, recalled: recalled))
            }
            
            if steps.count >= 2 {
                sequences.append(ReviewSequence(cardId: cardId, steps: steps))
            }
        }
        
        return sequences
    }
    
    // MARK: - Loss Evaluation (Binary Cross Entropy + L2 Regularization)
    static func evaluateLoss(weights: [Double], sequences: [ReviewSequence]) -> Double {
        var totalBCE = 0.0
        var count = 0
        let params = FSRSAlgorithm.Parameters(w: weights)
        
        for seq in sequences {
            guard seq.steps.count >= 2 else { continue }
            
            // First step initializes stability and difficulty
            let first = seq.steps[0]
            var s = FSRSAlgorithm.initialStability(grade: first.grade, parameters: params)
            var d = FSRSAlgorithm.initialDifficulty(grade: first.grade, parameters: params)
            
            for i in 1..<seq.steps.count {
                let step = seq.steps[i]
                let r = FSRSAlgorithm.retrievability(stability: s, elapsedDays: step.elapsedDays)
                
                // Clamped Log Loss
                let eps = 1e-6
                let clampedR = max(eps, min(1.0 - eps, r))
                let bce = -(step.recalled * log(clampedR) + (1.0 - step.recalled) * log(1.0 - clampedR))
                totalBCE += bce
                count += 1
                
                // Update s and d for next step
                d = FSRSAlgorithm.nextDifficulty(currentD: d, grade: step.grade, parameters: params)
                if step.grade == 1 {
                    s = FSRSAlgorithm.nextForgetStability(currentD: d, currentS: s, r: r, parameters: params)
                } else {
                    s = FSRSAlgorithm.nextRecallStability(currentD: d, currentS: s, r: r, grade: step.grade, parameters: params)
                }
            }
        }
        
        guard count > 0 else { return 0.0 }
        let avgBCE = totalBCE / Double(count)
        
        // L2 Regularization towards FSRS default parameters to prevent overfitting
        let defaultW = FSRSAlgorithm.Parameters.default.w
        var reg = 0.0
        for i in 0..<min(weights.count, defaultW.count) {
            let diff = weights[i] - defaultW[i]
            reg += diff * diff
        }
        let lambda = 0.005
        return avgBCE + lambda * reg
    }
    
    // MARK: - Numerical Optimization (Adam / Momentum Gradient Descent)
    private static func runGradientDescent(
        initialWeights: [Double],
        sequences: [ReviewSequence],
        maxIterations: Int = 40
    ) -> [Double] {
        var w = initialWeights
        let dim = w.count
        var m = [Double](repeating: 0.0, count: dim)
        var v = [Double](repeating: 0.0, count: dim)
        
        let beta1 = 0.9
        let beta2 = 0.999
        let eps = 1e-8
        let initialLR = 0.02
        
        // Only tune parameters that benefit most from student-specific tuning:
        // 0..3: Initial stabilities
        // 4..5: Initial difficulty & shape
        // 8..10: Recall stability multipliers
        // 15..16: Hard & Easy rating bonuses
        let tunableIndices: Set<Int> = [0, 1, 2, 3, 4, 5, 8, 9, 10, 15, 16]
        
        for epoch in 1...maxIterations {
            let lr = initialLR / (1.0 + 0.02 * Double(epoch))
            var grad = [Double](repeating: 0.0, count: dim)
            
            // Finite difference gradient estimation
            let baseLoss = evaluateLoss(weights: w, sequences: sequences)
            let h = 1e-4
            
            for i in tunableIndices {
                var wPlus = w
                wPlus[i] += h
                let lossPlus = evaluateLoss(weights: wPlus, sequences: sequences)
                grad[i] = (lossPlus - baseLoss) / h
            }
            
            // Adam update step
            for i in tunableIndices {
                m[i] = beta1 * m[i] + (1.0 - beta1) * grad[i]
                v[i] = beta2 * v[i] + (1.0 - beta2) * (grad[i] * grad[i])
                
                let mHat = m[i] / (1.0 - pow(beta1, Double(epoch)))
                let vHat = v[i] / (1.0 - pow(beta2, Double(epoch)))
                
                w[i] -= lr * mHat / (sqrt(vHat) + eps)
            }
            
            // Clamp parameters to reasonable physiological bounds
            w[0] = max(0.1, min(3.0, w[0]))    // Again stability: 0.1 .. 3.0 days
            w[1] = max(0.5, min(8.0, w[1]))    // Hard stability: 0.5 .. 8.0 days
            w[2] = max(1.0, min(15.0, w[2]))   // Good stability: 1.0 .. 15.0 days
            w[3] = max(3.0, min(50.0, w[3]))   // Easy stability: 3.0 .. 50.0 days
            w[4] = max(2.0, min(10.0, w[4]))   // Initial difficulty: 2.0 .. 10.0
            w[5] = max(0.1, min(2.0, w[5]))    // Difficulty sensitivity
            w[8] = max(0.5, min(3.0, w[8]))    // Recall stability multiplier
            w[9] = max(0.01, min(0.5, w[9]))   // Stability decay
            w[10] = max(0.5, min(2.5, w[10]))  // Retrievability sensitivity
            w[15] = max(0.1, min(0.8, w[15]))  // Hard bonus
            w[16] = max(1.5, min(5.0, w[16]))  // Easy bonus
        }
        
        return w
    }
    
    // MARK: - Synthetic Benchmark Calibration Dataset
    private static func generateCalibratedSyntheticSequences() -> [ReviewSequence] {
        return [
            ReviewSequence(
                cardId: UUID(),
                steps: [
                    ReviewStep(elapsedDays: 0.0, grade: 3, recalled: 1.0),
                    ReviewStep(elapsedDays: 3.2, grade: 3, recalled: 1.0),
                    ReviewStep(elapsedDays: 8.5, grade: 3, recalled: 1.0),
                    ReviewStep(elapsedDays: 22.0, grade: 2, recalled: 1.0),
                    ReviewStep(elapsedDays: 45.0, grade: 1, recalled: 0.0)
                ]
            ),
            ReviewSequence(
                cardId: UUID(),
                steps: [
                    ReviewStep(elapsedDays: 0.0, grade: 2, recalled: 1.0),
                    ReviewStep(elapsedDays: 1.2, grade: 3, recalled: 1.0),
                    ReviewStep(elapsedDays: 4.0, grade: 4, recalled: 1.0),
                    ReviewStep(elapsedDays: 16.0, grade: 3, recalled: 1.0)
                ]
            ),
            ReviewSequence(
                cardId: UUID(),
                steps: [
                    ReviewStep(elapsedDays: 0.0, grade: 1, recalled: 0.0),
                    ReviewStep(elapsedDays: 0.1, grade: 3, recalled: 1.0),
                    ReviewStep(elapsedDays: 2.5, grade: 3, recalled: 1.0),
                    ReviewStep(elapsedDays: 7.0, grade: 3, recalled: 1.0)
                ]
            )
        ]
    }
    
    // MARK: - Storage Helpers
    private static func saveOptimizationResult(_ result: OptimizationResult) {
        if let encodedWeights = try? JSONEncoder().encode(result.weights) {
            UserDefaults.standard.set(encodedWeights, forKey: "fsrsCustomWeights")
        }
        UserDefaults.standard.set(result.timestamp, forKey: "fsrsLastOptimizedDate")
        UserDefaults.standard.set(result.lossReductionPercent, forKey: "fsrsOptimizedLossReduction")
        UserDefaults.standard.set(result.sampleCount, forKey: "fsrsOptimizedSampleCount")
    }
}
