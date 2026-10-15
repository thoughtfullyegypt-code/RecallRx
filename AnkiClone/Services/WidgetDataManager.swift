import Foundation
import SwiftData
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Data snapshot used by iOS 17 Home & Lock Screen Widgets
struct WidgetSnapshotData: Codable, Sendable {
    let totalDue: Int
    let newCount: Int
    let learnCount: Int
    let reviewCount: Int
    let streakDays: Int
    let topDeckName: String
    let lastUpdated: Date
    
    static var placeholder: WidgetSnapshotData {
        WidgetSnapshotData(
            totalDue: 42,
            newCount: 15,
            learnCount: 7,
            reviewCount: 20,
            streakDays: 14,
            topDeckName: "USMLE Step 1 - Pathology",
            lastUpdated: Date()
        )
    }
}

/// Central manager for App Group storage, WidgetKit timeline reloading, and iOS Badge count synchronization
@MainActor
final class WidgetDataManager {
    static let shared = WidgetDataManager()
    
    // App Group identifier shared with Widget extension
    private let appGroupID = "group.com.recallrx.app"
    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
    }
    
    private let storageKey = "recallrx_widget_data"
    
    private init() {}
    
    // MARK: - Update Snapshot & Badge
    
    /// Scans the database and writes updated statistics for Home Screen widgets and the app icon badge
    func updateWidgetData(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        
        let cardDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                !card.isSuspended && !card.isBuried
            }
        )
        let cards = (try? context.fetch(cardDescriptor)) ?? []
        
        var totalDue = 0
        var newCount = 0
        var learnCount = 0
        var reviewCount = 0
        
        for card in cards {
            let state = card.state
            if state == .new {
                newCount += 1
                totalDue += 1
            } else if card.dueDate <= now {
                totalDue += 1
                if state == .learning || state == .relearning {
                    learnCount += 1
                } else {
                    reviewCount += 1
                }
            }
        }
        
        // Calculate streak from review logs
        let logDescriptor = FetchDescriptor<ReviewLog>(
            sortBy: [SortDescriptor(\.reviewDate, order: .reverse)]
        )
        let logs = (try? context.fetch(logDescriptor)) ?? []
        let streak = calculateStreak(logs: logs, calendar: calendar)
        
        // Determine top deck with most due cards
        let deckDescriptor = FetchDescriptor<Deck>()
        let decks = (try? context.fetch(deckDescriptor)) ?? []
        let topDeck = decks.max(by: { d1, d2 in
            let c1 = d1.cards.filter { !$0.isSuspended && !$0.isBuried && ($0.state == .new || $0.dueDate <= now) }.count
            let c2 = d2.cards.filter { !$0.isSuspended && !$0.isBuried && ($0.state == .new || $0.dueDate <= now) }.count
            return c1 < c2
        })?.name ?? "Medical Collection"
        
        let snapshot = WidgetSnapshotData(
            totalDue: totalDue,
            newCount: newCount,
            learnCount: learnCount,
            reviewCount: reviewCount,
            streakDays: streak,
            topDeckName: topDeck,
            lastUpdated: now
        )
        
        // Save to Shared UserDefaults for WidgetKit
        if let encoded = try? JSONEncoder().encode(snapshot) {
            sharedDefaults.set(encoded, forKey: storageKey)
        }
        
        // Synchronize App Icon Badge Count
        updateAppBadge(count: totalDue)
        
        // Reload Widget Timelines
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    /// Reads the current widget data snapshot
    func getWidgetData() -> WidgetSnapshotData {
        if let data = sharedDefaults.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshotData.self, from: data) {
            return snapshot
        }
        return WidgetSnapshotData.placeholder
    }
    
    // MARK: - Badge Count
    
    private func updateAppBadge(count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error = error {
                    print("[RecallRx] Error updating badge count: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Streak Calculation
    
    private func calculateStreak(logs: [ReviewLog], calendar: Calendar) -> Int {
        guard !logs.isEmpty else { return 0 }
        
        var uniqueDays: Set<Date> = []
        for log in logs {
            let startOfDay = calendar.startOfDay(for: log.reviewDate)
            uniqueDays.insert(startOfDay)
        }
        
        let sortedDays = uniqueDays.sorted(by: >)
        let today = calendar.startOfDay(for: Date())
        
        // Check if user reviewed today or yesterday
        guard let mostRecent = sortedDays.first,
              let dayDifference = calendar.dateComponents([.day], from: mostRecent, to: today).day,
              dayDifference <= 1 else {
            return 0
        }
        
        var currentStreak = 0
        var checkDate = mostRecent
        
        for day in sortedDays {
            if day == checkDate {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        
        return currentStreak
    }
}
