import Foundation
import SwiftData
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Persisted, real data shared with the Home and Lock Screen widgets.
struct WidgetSnapshotData: Codable, Sendable, Equatable {
    let totalDue: Int
    let newCount: Int
    let learnCount: Int
    let reviewCount: Int
    let streakDays: Int
    let topDeckName: String
    let lastUpdated: Date

    static var empty: WidgetSnapshotData {
        WidgetSnapshotData(totalDue: 0, newCount: 0, learnCount: 0, reviewCount: 0,
                           streakDays: 0, topDeckName: "", lastUpdated: .distantPast)
    }
}

/// Updates app-group snapshots, badges, and WidgetKit from the actual study queues.
@MainActor
final class WidgetDataManager {
    static let shared = WidgetDataManager(defaults: AppRuntime.defaults(suiteName: "group.com.recallrx.app"))

    private let defaults: UserDefaults
    let sideEffectsEnabled: Bool
    private let storageKey = "recallrx_widget_data"
    private(set) var lastError: String?

    init(defaults: UserDefaults, sideEffectsEnabled: Bool = true) {
        self.defaults = defaults
        self.sideEffectsEnabled = sideEffectsEnabled && !AppRuntime.isTesting
    }

    @discardableResult
    func updateWidgetData(context: ModelContext, now: Date = .now) -> WidgetSnapshotData {
        do {
            let decks = try context.fetch(FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.name)]))
            // Use the same limits, due dates, and exclusions as an actual study session.
            let queues = decks.map { (deck: $0, cards: Scheduler.getDueCards(from: $0, now: now)) }
            let cards = queues.flatMap { $0.cards }
            let logs = try context.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.reviewDate, order: .reverse)]))
            let newCount = cards.filter { $0.state == .new }.count
            let learnCount = cards.filter { $0.state == .learning || $0.state == .relearning }.count
            let reviewCount = cards.filter { $0.state == .review }.count
            let topDeck = queues.filter { !$0.cards.isEmpty }.sorted {
                if $0.cards.count != $1.cards.count { return $0.cards.count > $1.cards.count }
                return $0.deck.name.localizedCaseInsensitiveCompare($1.deck.name) == .orderedAscending
            }.first?.deck.displayName ?? ""
            let snapshot = WidgetSnapshotData(
                totalDue: cards.count, newCount: newCount, learnCount: learnCount,
                reviewCount: reviewCount, streakDays: calculateStreak(logs: logs, now: now),
                topDeckName: topDeck, lastUpdated: now
            )
            let previous = getWidgetData()
            defaults.set(try JSONEncoder().encode(snapshot), forKey: storageKey)
            lastError = nil

            if sideEffectsEnabled {
                updateAppBadge(count: snapshot.totalDue)
                if !sameContent(snapshot, previous) {
                    #if canImport(WidgetKit)
                    WidgetCenter.shared.reloadTimelines(ofKind: "RecallRxDue")
                    #endif
                }
            }
            return snapshot
        } catch {
            lastError = error.localizedDescription
            print("[WidgetDataManager] Could not update widget data: \(error.localizedDescription)")
            // A failed fetch must not replace a previously valid snapshot with fake zeroes.
            return getWidgetData()
        }
    }

    func getWidgetData() -> WidgetSnapshotData {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshotData.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private func sameContent(_ lhs: WidgetSnapshotData, _ rhs: WidgetSnapshotData) -> Bool {
        lhs.totalDue == rhs.totalDue && lhs.newCount == rhs.newCount
            && lhs.learnCount == rhs.learnCount && lhs.reviewCount == rhs.reviewCount
            && lhs.streakDays == rhs.streakDays && lhs.topDeckName == rhs.topDeckName
    }

    private func updateAppBadge(count: Int) {
        guard sideEffectsEnabled else { return }
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error {
                print("[WidgetDataManager] Could not update badge: \(error.localizedDescription)")
            }
        }
    }

    private func calculateStreak(logs: [ReviewLog], now: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = Set(logs.filter { $0.reviewDate <= now }.map { calendar.startOfDay(for: $0.reviewDate) })
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        guard let first = days.contains(today) ? today : (days.contains(yesterday) ? yesterday : nil) else { return 0 }
        var count = 0
        var current = first
        while days.contains(current) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { break }
            current = previous
        }
        return count
    }
}
