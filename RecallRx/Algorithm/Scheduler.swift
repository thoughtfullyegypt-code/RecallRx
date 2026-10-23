import Foundation
import SwiftData

final class Scheduler {
    // MARK: - Active Algorithm Configuration

    static var isFSRSEnabled: Bool { isFSRSEnabled(in: .standard) }
    static var isFSRSCustomized: Bool { isFSRSCustomized(in: .standard) }
    static var fsrsParameters: FSRSAlgorithm.Parameters { loadFSRSParameters(from: .standard) }

    static func isFSRSEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: "useFSRS") == nil || defaults.bool(forKey: "useFSRS")
    }

    static func isFSRSCustomized(in defaults: UserDefaults) -> Bool {
        defaults.data(forKey: "fsrsCustomWeights") != nil
    }

    static func loadFSRSParameters(from defaults: UserDefaults) -> FSRSAlgorithm.Parameters {
        let storedRetention = defaults.double(forKey: "fsrsTargetRetention")
        let targetRetention = storedRetention.isFinite && (0.80...0.97).contains(storedRetention)
            ? storedRetention : 0.90
        var parameters = FSRSAlgorithm.Parameters(targetRetention: targetRetention)
        if let data = defaults.data(forKey: "fsrsCustomWeights"),
           let weights = try? JSONDecoder().decode([Double].self, from: data),
           (weights.count == 21 || weights.count == 19),
           weights.allSatisfy(\.isFinite) {
            parameters.w = weights
        }
        return parameters
    }

    static func resetFSRSToDefault(in defaults: UserDefaults = .standard) {
        for key in ["fsrsCustomWeights", "fsrsLastOptimizedDate", "fsrsOptimizedLossReduction", "fsrsOptimizedSampleCount"] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Review Execution

    /// Advances scheduling only when the review and its log can be saved together.
    @discardableResult
    static func applyReview(
        card: Card,
        rating: SM2Algorithm.Rating,
        timeTakenMs: Int,
        context: ModelContext,
        now: Date = .now,
        defaults: UserDefaults = .standard,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        let snapshot = ReviewUndoSnapshot.capture(card)
        let intervalBefore = card.interval
        let easeFactorBefore = card.easeFactor
        let stateBefore = card.stateRaw
        let newInterval: Double
        let newEaseFactor: Double
        let newRepetitions: Int
        let newState: CardState
        let newLearningStep: Int

        if isFSRSEnabled(in: defaults) {
            let result = FSRSAlgorithm.review(card: card, rating: rating, parameters: loadFSRSParameters(from: defaults), now: now)
            newInterval = result.newInterval
            newEaseFactor = card.easeFactor
            newRepetitions = result.newReps
            newState = result.newState
            newLearningStep = result.newLearningStep
            card.fsrsStability = result.newStability
            card.fsrsDifficulty = result.newDifficulty
            card.fsrsReps = result.newReps
            card.fsrsLapses = result.newLapses
        } else {
            let result = SM2Algorithm.review(card: card, rating: rating, parameters: .load(from: defaults))
            newInterval = result.newInterval
            newEaseFactor = result.newEaseFactor
            newRepetitions = result.newRepetitions
            newState = result.newState
            newLearningStep = result.newLearningStep
        }

        if card.state == .review && rating == .again { card.lapseCount += 1 }
        card.interval = newInterval
        card.easeFactor = newEaseFactor
        card.repetitions = newRepetitions
        card.state = newState
        card.learningStep = newLearningStep
        card.lastReviewDate = now
        let scheduledInterval = newInterval >= 2 && newState == .review
            ? LoadBalancer.computeBalancedInterval(targetInterval: newInterval, deckCards: card.deck?.cards ?? [], referenceDate: now, defaults: defaults)
            : newInterval
        card.dueDate = now.addingTimeInterval(scheduledInterval * 86400)
        card.modifiedAt = now

        let log = ReviewLog(
            card: card,
            rating: rating.rawValue,
            reviewDate: now,
            timeTakenMs: max(0, timeTakenMs),
            intervalBefore: intervalBefore,
            intervalAfter: scheduledInterval,
            easeFactorBefore: easeFactorBefore,
            easeFactorAfter: newEaseFactor,
            cardStateBefore: stateBefore,
            cardStateAfter: newState.rawValue
        )
        context.insert(log)
        if !card.reviewLogs.contains(where: { $0.id == log.id }) { card.reviewLogs.append(log) }
        do {
            try save(context)
            ReviewUndoStore.save(id: log.id, snapshot: snapshot, persist: shouldPersistUndo(in: context))
            return true
        } catch {
            card.reviewLogs.removeAll { $0.id == log.id }
            context.delete(log)
            snapshot.restore(onto: card)
            return false
        }
    }

    static func nextIntervalDescription(
        card: Card,
        rating: SM2Algorithm.Rating,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> String {
        if isFSRSEnabled(in: defaults) {
            return FSRSAlgorithm.nextIntervalDescription(card: card, rating: rating, parameters: loadFSRSParameters(from: defaults), now: now)
        }
        return SM2Algorithm.nextIntervalDescription(card: card, rating: rating, parameters: .load(from: defaults))
    }

    // MARK: - Undo Review

    @discardableResult
    static func undoLastReview(
        card: Card,
        context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        guard let lastLog = card.reviewLogs.max(by: { $0.reviewDate < $1.reviewDate }),
              let snapshot = ReviewUndoStore.snapshot(id: lastLog.id, persist: shouldPersistUndo(in: context)) else {
            // Legacy logs cannot reconstruct all FSRS fields safely. Leave them intact.
            return false
        }
        // Finish unrelated pending edits before opening the undo transaction, so a
        // failed undo rollback cannot discard another screen's unsaved changes.
        do { try save(context) } catch { return false }
        snapshot.restore(onto: card)
        card.modifiedAt = now
        card.reviewLogs.removeAll { $0.id == lastLog.id }
        // Keep the log attached to its context until the restored card can be saved.
        context.delete(lastLog)
        do {
            try save(context)
            ReviewUndoStore.remove(id: lastLog.id, persist: shouldPersistUndo(in: context))
            return true
        } catch {
            // A failed transactional save must not report a successful undo.
            context.rollback()
            return false
        }
    }

    private static func shouldPersistUndo(in context: ModelContext) -> Bool {
        !context.container.configurations.allSatisfy(\.isStoredInMemoryOnly)
    }

    // MARK: - Calendar-Day Limits

    static func dailyUsage(for deck: Deck, now: Date = .now, calendar: Calendar = .current) -> DailyStudyUsage {
        let start = calendar.startOfDay(for: now)
        var introduced: Set<UUID> = []
        var reviewed: Set<UUID> = []
        for card in deck.cards {
            for log in card.reviewLogs where log.reviewDate >= start && log.reviewDate <= now {
                if log.cardStateBefore == CardState.new.rawValue { introduced.insert(card.id) }
                if log.cardStateBefore == CardState.review.rawValue { reviewed.insert(card.id) }
            }
        }
        return DailyStudyUsage(introducedCardIDs: introduced, reviewedCardIDs: reviewed, newLimit: max(0, deck.newCardsPerDay), reviewLimit: max(0, deck.reviewsPerDay))
    }

    static func getDueCards(from deck: Deck, now: Date = .now, calendar: Calendar = .current) -> [Card] {
        let usage = dailyUsage(for: deck, now: now, calendar: calendar)
        return getLearningCards(from: deck, now: now, calendar: calendar)
            + reviewCards(from: deck, limit: deck.reviewsPerDay, usage: usage, now: now, calendar: calendar)
            + newCards(from: deck, limit: deck.newCardsPerDay, usage: usage, now: now, calendar: calendar)
    }

    static func getLearningCards(from deck: Deck, dueOnly: Bool = true, now: Date = .now, calendar: Calendar = .current) -> [Card] {
        deck.cards.filter {
            !$0.isSuspended && !isBuried($0, at: now, calendar: calendar)
                && ($0.state == .learning || $0.state == .relearning)
                && (!dueOnly || $0.dueDate <= now)
        }.sorted { $0.dueDate < $1.dueDate }
    }

    static func getReviewCards(from deck: Deck, limit: Int, now: Date = .now, calendar: Calendar = .current) -> [Card] {
        reviewCards(from: deck, limit: limit, usage: dailyUsage(for: deck, now: now, calendar: calendar), now: now, calendar: calendar)
    }

    private static func reviewCards(from deck: Deck, limit: Int, usage: DailyStudyUsage, now: Date, calendar: Calendar) -> [Card] {
        guard limit > 0 else { return [] }
        var remaining = max(0, limit - usage.reviewedCardIDs.count)
        let due = deck.cards.filter {
            !$0.isSuspended && !isBuried($0, at: now, calendar: calendar) && $0.state == .review && $0.dueDate <= now
        }.sorted { $0.dueDate < $1.dueDate }
        return due.filter { card in
            if usage.reviewedCardIDs.contains(card.id) { return true }
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
    }

    static func getNewCards(from deck: Deck, limit: Int, now: Date = .now, calendar: Calendar = .current) -> [Card] {
        newCards(from: deck, limit: limit, usage: dailyUsage(for: deck, now: now, calendar: calendar), now: now, calendar: calendar)
    }

    private static func newCards(from deck: Deck, limit: Int, usage: DailyStudyUsage, now: Date, calendar: Calendar) -> [Card] {
        let remaining = max(0, limit - usage.introducedCardIDs.count)
        guard remaining > 0 else { return [] }
        let cards = deck.cards.filter {
            !$0.isSuspended && !isBuried($0, at: now, calendar: calendar) && $0.state == .new && $0.createdAt <= now
        }.sorted { $0.createdAt < $1.createdAt }
        return Array(cards.prefix(remaining))
    }

    // MARK: - Card Actions

    static func isBuried(_ card: Card, at now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard card.isBuried else { return false }
        let expiry = card.buriedUntil ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: card.modifiedAt)) ?? .distantFuture
        return now < expiry
    }

    static func buryCard(_ card: Card, now: Date = .now, calendar: Calendar = .current) {
        card.isBuried = true
        card.buriedUntil = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        card.modifiedAt = now
    }

    @discardableResult
    static func unburyExpiredCards(in deck: Deck, now: Date = .now, calendar: Calendar = .current) -> Bool {
        var changed = false
        for card in deck.cards where card.isBuried && !isBuried(card, at: now, calendar: calendar) {
            unburyCard(card, now: now)
            changed = true
        }
        return changed
    }

    static func unburyCard(_ card: Card, now: Date = .now) {
        card.isBuried = false
        card.buriedUntil = nil
        card.modifiedAt = now
    }

    static func suspendCard(_ card: Card, now: Date = .now) {
        card.isSuspended = true
        card.modifiedAt = now
    }

    static func unsuspendCard(_ card: Card, now: Date = .now) {
        card.isSuspended = false
        card.modifiedAt = now
    }

    static func unburyAllCards(in deck: Deck, now: Date = .now) {
        for card in deck.cards where card.isBuried { unburyCard(card, now: now) }
    }
}

private struct ReviewUndoSnapshot: Codable {
    let savedAt: Date?
    let modifiedAt: Date?
    let interval: Double
    let easeFactor: Double
    let repetitions: Int
    let stateRaw: String
    let learningStep: Int
    let dueDate: Date
    let lastReviewDate: Date?
    let fsrsStability: Double
    let fsrsDifficulty: Double
    let fsrsReps: Int
    let fsrsLapses: Int
    let lapseCount: Int

    static func capture(_ card: Card) -> ReviewUndoSnapshot {
        ReviewUndoSnapshot(
            savedAt: .now,
            modifiedAt: card.modifiedAt,
            interval: card.interval,
            easeFactor: card.easeFactor,
            repetitions: card.repetitions,
            stateRaw: card.stateRaw,
            learningStep: card.learningStep,
            dueDate: card.dueDate,
            lastReviewDate: card.lastReviewDate,
            fsrsStability: card.fsrsStability,
            fsrsDifficulty: card.fsrsDifficulty,
            fsrsReps: card.fsrsReps,
            fsrsLapses: card.fsrsLapses,
            lapseCount: card.lapseCount
        )
    }

    func restore(onto card: Card) {
        if let modifiedAt { card.modifiedAt = modifiedAt }
        card.interval = interval
        card.easeFactor = easeFactor
        card.repetitions = repetitions
        card.stateRaw = stateRaw
        card.learningStep = learningStep
        card.dueDate = dueDate
        card.lastReviewDate = lastReviewDate
        card.fsrsStability = fsrsStability
        card.fsrsDifficulty = fsrsDifficulty
        card.fsrsReps = fsrsReps
        card.fsrsLapses = fsrsLapses
        card.lapseCount = lapseCount
    }
}

private enum ReviewUndoStore {
    private static var memory: [UUID: ReviewUndoSnapshot] = [:]

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("recallrx-undo-snapshots.json")
    }

    private static func load() -> [String: ReviewUndoSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: ReviewUndoSnapshot].self, from: data) else { return [:] }
        return decoded
    }

    static func save(id: UUID, snapshot: ReviewUndoSnapshot, persist: Bool) {
        memory[id] = snapshot
        guard persist else { return }
        var all = load()
        all[id.uuidString] = snapshot
        if all.count > 400 {
            let extras = all.sorted { ($0.value.savedAt ?? .distantPast) < ($1.value.savedAt ?? .distantPast) }
                .prefix(all.count - 400)
            for entry in extras { all.removeValue(forKey: entry.key) }
        }
        write(all)
    }

    static func snapshot(id: UUID, persist: Bool) -> ReviewUndoSnapshot? {
        memory[id] ?? (persist ? load()[id.uuidString] : nil)
    }

    static func remove(id: UUID, persist: Bool) {
        memory.removeValue(forKey: id)
        guard persist else { return }
        var all = load()
        all.removeValue(forKey: id.uuidString)
        write(all)
    }

    private static func write(_ snapshots: [String: ReviewUndoSnapshot]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
