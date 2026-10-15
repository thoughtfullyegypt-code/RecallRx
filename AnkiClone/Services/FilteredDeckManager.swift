import Foundation
import SwiftData

/// Custom Study / Filtered Cram Deck Configuration
struct FilteredDeckConfig: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var searchFilter: String
    var cardLimit: Int
    var rescheduleCards: Bool // If false, studying DOES NOT advance permanent FSRS intervals
    var order: CramOrder
    
    enum CramOrder: String, Codable, CaseIterable {
        case random = "Random"
        case dueFirst = "Due First"
        case mostLapses = "Most Lapses (Weakest)"
        case oldestSeen = "Oldest Seen First"
    }
}

/// Exam Date Target Pace Calculation Result
struct ExamPaceResult: Sendable {
    let daysRemaining: Int
    let totalUnseenCards: Int
    let totalReviewCards: Int
    let recommendedDailyNew: Int
    let recommendedRetention: Double
    let message: String
}

/// Filtered Deck & Exam-Date Target Engine for RecallRx
final class FilteredDeckManager {
    
    // MARK: - Filtered Deck Card Retrieval
    
    static func buildFilteredCards(
        config: FilteredDeckConfig,
        allCards: [Card],
        referenceDate: Date = Date()
    ) -> [Card] {
        // 1. Filter using search syntax
        var matched = SearchSyntaxParser.filter(cards: allCards, query: config.searchFilter, referenceDate: referenceDate)
        
        // 2. Sort by specified cram order
        switch config.order {
        case .random:
            matched.shuffle()
        case .dueFirst:
            matched.sort { $0.dueDate < $1.dueDate }
        case .mostLapses:
            matched.sort { $0.lapseCount > $1.lapseCount }
        case .oldestSeen:
            matched.sort { ($0.lastReviewDate ?? .distantPast) < ($1.lastReviewDate ?? .distantPast) }
        }
        
        // 3. Apply card limit
        if config.cardLimit > 0 && matched.count > config.cardLimit {
            return Array(matched.prefix(config.cardLimit))
        }
        
        return matched
    }
    
    // MARK: - Exam-Date Target Calculator
    
    /// Calculates the daily new card pace and recommended retention to finish a deck before an exam date
    static func calculateExamPace(
        examDate: Date,
        deck: Deck,
        bufferDays: Int = 7, // Leave 1 week for pure dedicated practice tests
        referenceDate: Date = Date()
    ) -> ExamPaceResult {
        let calendar = Calendar.current
        let startOfRef = calendar.startOfDay(for: referenceDate)
        let startOfExam = calendar.startOfDay(for: examDate)
        let daysUntilExam = calendar.dateComponents([.day], from: startOfRef, to: startOfExam).day ?? 0
        let effectiveDays = max(1, daysUntilExam - bufferDays)
        
        let unseenCount = deck.cards.filter { $0.state == .new }.count
        let reviewCount = deck.cards.filter { $0.state == .review || $0.state == .learning }.count
        
        let dailyNew = Int(ceil(Double(unseenCount) / Double(effectiveDays)))
        
        // Reddit community standard: 0.88 target retention for optimal workload-to-retention balance
        let recommendedRetention = 0.88
        
        let message: String
        if daysUntilExam <= 0 {
            message = "Exam date is today or in the past!"
        } else if daysUntilExam <= bufferDays {
            message = "⚠️ Exam is in \(daysUntilExam) days! Recommended to switch to pure Cram Mode for high-yield weak areas."
        } else {
            message = "At \(dailyNew) new cards/day, you will complete all \(unseenCount) unseen cards \(bufferDays) days before your exam date for final dedicated review."
        }
        
        return ExamPaceResult(
            daysRemaining: daysUntilExam,
            totalUnseenCards: unseenCount,
            totalReviewCards: reviewCount,
            recommendedDailyNew: dailyNew,
            recommendedRetention: recommendedRetention,
            message: message
        )
    }
}
