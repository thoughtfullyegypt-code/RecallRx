import Foundation
import SwiftData

/// Burnout Shield & Load Balancer Engine
/// Inspired by medical student Reddit research (r/medicalschoolanki, r/step1)
/// Smooths review distribution to prevent "Review Hell" and card clustering after hospital rotations.
final class LoadBalancer {
    
    // MARK: - Configuration
    static var isEnabled: Bool {
        get {
            isEnabled(in: .standard)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "enableLoadBalancer")
        }
    }
    
    static var maxDailyReviews: Int {
        get {
            maxDailyReviews(in: .standard)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "burnoutShieldMaxDaily")
        }
    }
    
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "enableLoadBalancer") == nil || defaults.bool(forKey: "enableLoadBalancer")
    }

    static func maxDailyReviews(in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: "burnoutShieldMaxDaily")
        return value > 0 ? value : 150
    }

    // MARK: - Fuzz Interval Calculation
    
    /// Computes allowable fuzz range around a target interval (in days)
    /// Follows standard Anki fuzz distribution:
    /// - < 2 days: 0 fuzz
    /// - 2 days: ±0.5 day (2-3 days)
    /// - 3...7 days: ±1 day
    /// - 7...20 days: ±15% of interval
    /// - > 20 days: ±5% of interval (clamped to max 14 days)
    static func computeFuzzRange(for interval: Double) -> ClosedRange<Double> {
        guard interval >= 2.0 else {
            return interval...interval
        }
        
        let delta: Double
        if interval < 3.0 {
            delta = 0.5
        } else if interval <= 7.0 {
            delta = 1.0
        } else if interval <= 20.0 {
            delta = max(1.0, interval * 0.15)
        } else {
            delta = min(14.0, max(2.0, interval * 0.05))
        }
        
        let minInterval = max(1.0, floor(interval - delta))
        let maxInterval = ceil(interval + delta)
        return minInterval...maxInterval
    }
    
    /// Selects optimal review interval within the fuzz window that minimizes review count on the destination day.
    static func computeBalancedInterval(
        targetInterval: Double,
        deckCards: [Card],
        calendar: Calendar = .current,
        referenceDate: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Double {
        guard isEnabled(in: defaults) && targetInterval >= 2.0 else {
            return targetInterval
        }
        
        let fuzzRange = computeFuzzRange(for: targetInterval)
        let minDay = Int(fuzzRange.lowerBound)
        let maxDay = Int(fuzzRange.upperBound)
        
        if minDay == maxDay {
            return Double(minDay)
        }
        
        // Count how many cards are already scheduled for each candidate day
        var dayCounts: [Int: Int] = [:]
        for d in minDay...maxDay {
            dayCounts[d] = 0
        }
        
        let startOfRef = calendar.startOfDay(for: referenceDate)
        
        for card in deckCards where !card.isSuspended && card.state == .review {
            let daysFromRef = calendar.dateComponents([.day], from: startOfRef, to: calendar.startOfDay(for: card.dueDate)).day ?? 0
            if daysFromRef >= minDay && daysFromRef <= maxDay {
                dayCounts[daysFromRef, default: 0] += 1
            }
        }
        
        // Find candidate day with the lowest card count (ties broken toward target interval)
        var bestDay = Int(round(targetInterval))
        var minCount = Int.max
        
        for d in minDay...maxDay {
            let count = dayCounts[d, default: 0]
            if count < minCount {
                minCount = count
                bestDay = d
            } else if count == minCount {
                // Pick one closest to targetInterval
                if abs(Double(d) - targetInterval) < abs(Double(bestDay) - targetInterval) {
                    bestDay = d
                }
            }
        }
        
        return Double(bestDay)
    }
    
    // MARK: - Burnout Shield: Overdue Backlog Redistribution
    
    /// Redistributes accumulated overdue review cards across future days to prevent study burnout
    /// High-stability cards are pushed further into the future; fragile cards stay closer to today.
    @discardableResult
    static func redistributeOverdueBacklog(
        in deck: Deck,
        maxDailyCap: Int? = nil,
        context: ModelContext,
        calendar: Calendar = .current,
        referenceDate: Date = .now,
        defaults: UserDefaults = .standard
    ) -> Int {
        let cap = maxDailyCap ?? maxDailyReviews(in: defaults)
        guard cap > 0 else { return 0 }
        
        let now = referenceDate
        let overdueCards = deck.cards
            .filter { !$0.isSuspended && !Scheduler.isBuried($0, at: now, calendar: calendar) && $0.state == .review && $0.dueDate < now }
            .sorted { $0.fsrsStability < $1.fsrsStability }
        
        guard overdueCards.count > cap else {
            return 0 // No redistribution needed if under daily cap
        }
        
        let excessCount = overdueCards.count - cap
        let cardsToDistribute = Array(overdueCards.suffix(excessCount))
        
        // Spread excess cards across the next 1 to 5 days evenly
        let daysToSpread = min(7, max(2, Int(ceil(Double(excessCount) / Double(cap)))))
        
        for (index, card) in cardsToDistribute.enumerated() {
            let dayOffset = (index % daysToSpread) + 1
            if let newDate = calendar.date(byAdding: .day, value: dayOffset, to: now) {
                card.dueDate = newDate
                card.modifiedAt = now
            }
        }
        
        try? context.save()
        return excessCount
    }
}
