import Foundation
import SwiftData
import Observation

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "1 Week"
    case month = "1 Month"
    case quarter = "3 Months"
    case year = "1 Year"
    case allTime = "All Time"
    
    var id: String { rawValue }
    
    var dayCount: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .allTime: return nil
        }
    }
}

@Observable
final class StatsViewModel {
    var modelContext: ModelContext
    var selectedDeck: Deck?
    var selectedPeriod: StatsPeriod = .month
    var reviewLogs: [ReviewLog] = []
    var allCards: [Card] = []
    
    init(modelContext: ModelContext, selectedDeck: Deck? = nil) {
        self.modelContext = modelContext
        self.selectedDeck = selectedDeck
        fetchData()
    }
    
    // MARK: - Data Fetching
    
    func fetchData() {
        do {
            let logDescriptor = FetchDescriptor<ReviewLog>(
                sortBy: [SortDescriptor(\.reviewDate, order: .reverse)]
            )
            reviewLogs = try modelContext.fetch(logDescriptor)
            
            let cardDescriptor = FetchDescriptor<Card>()
            allCards = try modelContext.fetch(cardDescriptor)
        } catch {
            reviewLogs = []
            allCards = []
        }
    }
    
    // MARK: - Scoped Data Accessors
    
    var filteredCards: [Card] {
        if let selectedDeck = selectedDeck {
            return allCards.filter { $0.deck?.id == selectedDeck.id }
        }
        return allCards
    }
    
    var deckFilteredLogs: [ReviewLog] {
        if let selectedDeck = selectedDeck {
            return reviewLogs.filter { $0.card?.deck?.id == selectedDeck.id }
        }
        return reviewLogs
    }
    
    var periodFilteredLogs: [ReviewLog] {
        let logs = deckFilteredLogs
        guard let days = selectedPeriod.dayCount else { return logs }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        return logs.filter { $0.reviewDate >= cutoff }
    }
    
    var todayLogs: [ReviewLog] {
        deckFilteredLogs.filter { Calendar.current.isDateInToday($0.reviewDate) }
    }
    
    // MARK: - Today's Summary
    
    var totalReviewsToday: Int {
        todayLogs.count
    }
    
    var totalStudyTimeToday: TimeInterval {
        Double(todayLogs.reduce(0) { $0 + $1.timeTakenMs }) / 1000.0
    }
    
    var todayNewCards: Int {
        todayLogs.filter { $0.cardStateBefore == CardState.new.rawValue }.count
    }
    
    var todayReviewCards: Int {
        todayLogs.filter { $0.cardStateBefore == CardState.review.rawValue }.count
    }
    
    var todayLearningCards: Int {
        todayLogs.filter {
            $0.cardStateBefore == CardState.learning.rawValue ||
            $0.cardStateBefore == CardState.relearning.rawValue
        }.count
    }
    
    // MARK: - Performance Metrics
    
    var averageTimePerCard: Double {
        let logs = periodFilteredLogs
        guard !logs.isEmpty else { return 0.0 }
        let totalMs = logs.reduce(0) { $0 + $1.timeTakenMs }
        return Double(totalMs) / Double(logs.count) / 1000.0
    }
    
    var retentionRate: Double {
        let logs = periodFilteredLogs
        guard !logs.isEmpty else { return 0.0 }
        let nonAgainCount = logs.filter { $0.rating != SM2Algorithm.Rating.again.rawValue }.count
        return (Double(nonAgainCount) / Double(logs.count)) * 100.0
    }
    
    var averageEaseFactor: Double {
        let cards = filteredCards
        guard !cards.isEmpty else { return 2.5 }
        let sum = cards.reduce(0.0) { $0 + $1.easeFactor }
        return sum / Double(cards.count)
    }
    
    var totalCardsStudied: Int {
        Set(periodFilteredLogs.compactMap { $0.card?.id }).count
    }
    
    var streakDays: Int {
        let calendar = Calendar.current
        let studyDays = Set(deckFilteredLogs.map { calendar.startOfDay(for: $0.reviewDate) })
        
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        
        let startingDay: Date?
        if studyDays.contains(today) {
            startingDay = today
        } else if studyDays.contains(yesterday) {
            startingDay = yesterday
        } else {
            startingDay = nil
        }
        
        guard var checkDate = startingDay else { return 0 }
        
        var streak = 0
        while studyDays.contains(checkDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }
        return streak
    }
    
    // MARK: - Distributions
    
    var cardStateDistribution: (new: Int, learning: Int, young: Int, mature: Int) {
        var newCount = 0
        var learningCount = 0
        var youngCount = 0
        var matureCount = 0
        
        for card in filteredCards {
            switch card.state {
            case .new:
                newCount += 1
            case .learning, .relearning:
                learningCount += 1
            case .review:
                if card.interval >= 21.0 {
                    matureCount += 1
                } else {
                    youngCount += 1
                }
            }
        }
        return (new: newCount, learning: learningCount, young: youngCount, mature: matureCount)
    }
    
    var easeDistribution: [(range: String, count: Int)] {
        let cards = filteredCards.filter { $0.state != .new }
        var bucket1 = 0
        var bucket2 = 0
        var bucket3 = 0
        var bucket4 = 0
        var bucket5 = 0
        
        for card in cards {
            if card.easeFactor < 1.80 {
                bucket1 += 1
            } else if card.easeFactor < 2.10 {
                bucket2 += 1
            } else if card.easeFactor < 2.50 {
                bucket3 += 1
            } else if card.easeFactor < 2.80 {
                bucket4 += 1
            } else {
                bucket5 += 1
            }
        }
        
        return [
            (range: "< 180%", count: bucket1),
            (range: "180% - 210%", count: bucket2),
            (range: "210% - 250%", count: bucket3),
            (range: "250% - 280%", count: bucket4),
            (range: "≥ 280%", count: bucket5)
        ]
    }
    
    var intervalDistribution: [(range: String, count: Int)] {
        let cards = filteredCards.filter { $0.state == .review }
        var range1 = 0
        var range2 = 0
        var range3 = 0
        var range4 = 0
        var range5 = 0
        
        for card in cards {
            let days = card.interval
            if days <= 7.0 {
                range1 += 1
            } else if days < 21.0 {
                range2 += 1
            } else if days <= 60.0 {
                range3 += 1
            } else if days <= 180.0 {
                range4 += 1
            } else {
                range5 += 1
            }
        }
        
        return [
            (range: "1 - 7 d", count: range1),
            (range: "8 - 20 d", count: range2),
            (range: "21 - 60 d", count: range3),
            (range: "61 - 180 d", count: range4),
            (range: "180+ d", count: range5)
        ]
    }
    
    var hourlyBreakdown: [(hour: Int, count: Int)] {
        let calendar = Calendar.current
        var hourCounts = [Int: Int]()
        for log in periodFilteredLogs {
            let hour = calendar.component(.hour, from: log.reviewDate)
            hourCounts[hour, default: 0] += 1
        }
        return (0..<24).map { hour in
            (hour: hour, count: hourCounts[hour, default: 0])
        }
    }
    
    // MARK: - Charts & Projections
    
    var reviewsPerDay: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let daysLimit = selectedPeriod.dayCount ?? 30
        
        var dateMap = [Date: Int]()
        for log in periodFilteredLogs {
            let day = calendar.startOfDay(for: log.reviewDate)
            dateMap[day, default: 0] += 1
        }
        
        var result: [(date: Date, count: Int)] = []
        for offset in (0...daysLimit).reversed() {
            if let date = calendar.date(byAdding: .day, value: -offset, to: .now) {
                let day = calendar.startOfDay(for: date)
                result.append((date: day, count: dateMap[day, default: 0]))
            }
        }
        return result
    }
    
    var heatmapData: [Date: Int] {
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .day, value: -365, to: .now) ?? .now
        var map: [Date: Int] = [:]
        
        for log in deckFilteredLogs where log.reviewDate >= oneYearAgo {
            let day = calendar.startOfDay(for: log.reviewDate)
            map[day, default: 0] += 1
        }
        return map
    }
    
    var forecastData: [(date: Date, dueCount: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var forecastMap = [Date: Int]()
        
        for card in filteredCards where !card.isSuspended {
            let dueDay = calendar.startOfDay(for: card.dueDate)
            if dueDay >= today {
                forecastMap[dueDay, default: 0] += 1
            }
        }
        
        var result: [(date: Date, dueCount: Int)] = []
        for offset in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: offset, to: today) {
                result.append((date: date, dueCount: forecastMap[date, default: 0]))
            }
        }
        return result
    }
}
