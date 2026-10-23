import Foundation
import SwiftData
import XCTest
@testable import RecallRx

final class SchedulingRegressionTests: XCTestCase {
    @MainActor
    func testLearningWaitsForItsActualDueTimeInBothSchedulers() throws {
        for useFSRS in [false, true] {
            let fixture = try SchedulingFixture(useFSRS: useFSRS)
            defer { fixture.cleanUp() }
            var now = fixture.now
            let card = fixture.card("One")
            try fixture.context.save()
            let session = StudyViewModel(deck: fixture.deck, modelContext: fixture.context, now: { now }, calendar: fixture.calendar, defaults: fixture.defaults)
            session.showAnswer()
            XCTAssertTrue(session.rateCard(.again))
            XCTAssertNil(session.currentCard)
            XCTAssertTrue(session.isWaitingForLearning)
            XCTAssertFalse(session.isComplete)
            XCTAssertEqual(card.dueDate.timeIntervalSince(now), 60, accuracy: 0.001)
            now = now.addingTimeInterval(59)
            session.refreshDueCards()
            XCTAssertNil(session.currentCard)
            now = now.addingTimeInterval(1)
            session.refreshDueCards()
            XCTAssertEqual(session.currentCard?.id, card.id)
            XCTAssertFalse(session.isShowingAnswer)
            session.showAnswer()
            XCTAssertTrue(session.rateCard(.good))
            XCTAssertNil(session.currentCard)
            XCTAssertEqual(card.dueDate.timeIntervalSince(now), 600, accuracy: 0.001)
        }
    }

    @MainActor
    func testUndoRestoresQueueCountersAndSchedulingWithoutDuplicates() throws {
        let fixture = try SchedulingFixture()
        defer { fixture.cleanUp() }
        let first = fixture.card("First", createdAt: fixture.now.addingTimeInterval(-20))
        let second = fixture.card("Second", createdAt: fixture.now.addingTimeInterval(-10))
        let originalDue = first.dueDate
        try fixture.context.save()
        let session = fixture.session()
        XCTAssertEqual(session.currentCard?.id, first.id)
        session.showAnswer()
        XCTAssertTrue(session.rateCard(.again))
        XCTAssertEqual(session.currentCard?.id, second.id)
        XCTAssertEqual(session.againCount, 1)
        session.undoLastReview()
        XCTAssertEqual(session.currentCard?.id, first.id)
        XCTAssertEqual(session.studyQueue.map(\.id), [second.id])
        XCTAssertEqual(session.cardsStudied, 0)
        XCTAssertEqual(session.correctCount, 0)
        XCTAssertEqual(session.againCount, 0)
        XCTAssertEqual(first.state, .new)
        XCTAssertEqual(first.dueDate, originalDue)
        XCTAssertEqual(first.fsrsStability, 0)
        XCTAssertTrue(first.reviewLogs.isEmpty)
        session.showAnswer()
        XCTAssertTrue(session.rateCard(.easy))
        XCTAssertEqual(session.currentCard?.id, second.id)
        XCTAssertFalse(session.studyQueue.contains { $0.id == first.id })
        session.showAnswer()
        XCTAssertTrue(session.rateCard(.easy))
        XCTAssertTrue(session.isComplete)
    }

    @MainActor
    func testDailyNewLimitSurvivesOpeningAnotherSessionAndContext() throws {
        let fixture = try SchedulingFixture(newLimit: 1)
        defer { fixture.cleanUp() }
        _ = fixture.card("First", createdAt: fixture.now.addingTimeInterval(-20))
        _ = fixture.card("Second", createdAt: fixture.now.addingTimeInterval(-10))
        try fixture.context.save()
        let session = fixture.session()
        session.showAnswer()
        XCTAssertTrue(session.rateCard(.easy))
        XCTAssertTrue(session.isComplete)
        let reopenedContext = ModelContext(fixture.container)
        let reopenedDeck = try XCTUnwrap(reopenedContext.fetch(FetchDescriptor<Deck>()).first)
        let reopened = StudyViewModel(deck: reopenedDeck, modelContext: reopenedContext, now: { fixture.now }, calendar: fixture.calendar, defaults: fixture.defaults)
        XCTAssertNil(reopened.currentCard)
        XCTAssertEqual(Scheduler.dailyUsage(for: reopenedDeck, now: fixture.now, calendar: fixture.calendar).remainingNew, 0)
    }

    @MainActor
    func testReviewBudgetCountsFirstAttemptsAndKeepsDueFollowUps() throws {
        let fixture = try SchedulingFixture(reviewLimit: 1)
        defer { fixture.cleanUp() }
        let alreadyReviewed = fixture.card("Reviewed", state: .review)
        let unseenReview = fixture.card("Fresh review", state: .review)
        fixture.log(on: alreadyReviewed, at: fixture.now.addingTimeInterval(-120), before: .review)
        fixture.log(on: alreadyReviewed, at: fixture.now.addingTimeInterval(-60), before: .review)
        try fixture.context.save()
        let usage = Scheduler.dailyUsage(for: fixture.deck, now: fixture.now, calendar: fixture.calendar)
        XCTAssertEqual(usage.reviewedCardIDs.count, 1)
        XCTAssertEqual(usage.remainingReviews, 0)
        let available = Scheduler.getReviewCards(from: fixture.deck, limit: 1, now: fixture.now, calendar: fixture.calendar)
        XCTAssertEqual(available.map(\.id), [alreadyReviewed.id])
        XCTAssertFalse(available.contains { $0.id == unseenReview.id })
    }

    @MainActor
    func testCalendarDayResetAndFutureDatedLogs() throws {
        let fixture = try SchedulingFixture(newLimit: 1)
        defer { fixture.cleanUp() }
        let introduced = fixture.card("Introduced", state: .review, dueDate: fixture.now.addingTimeInterval(86400 * 30))
        let fresh = fixture.card("Fresh")
        fixture.log(on: introduced, at: fixture.now.addingTimeInterval(60), before: .new)
        XCTAssertEqual(Scheduler.getNewCards(from: fixture.deck, limit: 1, now: fixture.now, calendar: fixture.calendar).map(\.id), [fresh.id])
        fixture.log(on: introduced, at: fixture.now.addingTimeInterval(-60), before: .new)
        XCTAssertTrue(Scheduler.getNewCards(from: fixture.deck, limit: 1, now: fixture.now, calendar: fixture.calendar).isEmpty)
        let tomorrow = try XCTUnwrap(fixture.calendar.date(byAdding: .day, value: 1, to: fixture.now))
        XCTAssertEqual(Scheduler.getNewCards(from: fixture.deck, limit: 1, now: tomorrow, calendar: fixture.calendar).map(\.id), [fresh.id])
    }

    @MainActor
    func testAutoAdvanceOffSavesOnceAndWaitsForNext() throws {
        let fixture = try SchedulingFixture(autoAdvance: false)
        defer { fixture.cleanUp() }
        let first = fixture.card("First", createdAt: fixture.now.addingTimeInterval(-20))
        let second = fixture.card("Second", createdAt: fixture.now.addingTimeInterval(-10))
        try fixture.context.save()
        let session = fixture.session()
        session.showAnswer()
        XCTAssertTrue(session.rateCard(.easy))
        XCTAssertTrue(session.hasRatedCurrentCard)
        XCTAssertEqual(session.currentCard?.id, first.id)
        XCTAssertFalse(session.rateCard(.again))
        XCTAssertEqual(first.reviewLogs.count, 1)
        session.nextCard()
        XCTAssertFalse(session.hasRatedCurrentCard)
        XCTAssertEqual(session.currentCard?.id, second.id)
    }

    @MainActor
    func testBuryExpiresAtLocalMidnightAcrossDaylightSaving() throws {
        let fixture = try SchedulingFixture()
        defer { fixture.cleanUp() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T06:30:00Z"))
        let midnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-09T04:00:00Z"))
        let card = fixture.card("Buried")
        Scheduler.buryCard(card, now: now, calendar: calendar)
        XCTAssertEqual(card.buriedUntil, midnight)
        card.modifiedAt = now.addingTimeInterval(3600) // Editing does not extend burial.
        XCTAssertTrue(Scheduler.isBuried(card, at: midnight.addingTimeInterval(-1), calendar: calendar))
        XCTAssertFalse(Scheduler.isBuried(card, at: midnight, calendar: calendar))
        XCTAssertTrue(Scheduler.unburyExpiredCards(in: fixture.deck, now: midnight, calendar: calendar))
        XCTAssertFalse(card.isBuried)
        XCTAssertNil(card.buriedUntil)
    }

    @MainActor
    func testSM2PreferencesAffectReviewsAndIntervalPreviews() throws {
        let fixture = try SchedulingFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("2m 20m", forKey: "learningSteps")
        fixture.defaults.set(7, forKey: "graduatingInterval")
        fixture.defaults.set(30, forKey: "easyInterval")
        let card = fixture.card("Configured")
        let parameters = SM2SchedulingParameters.load(from: fixture.defaults)
        XCTAssertEqual(SM2Algorithm.review(card: card, rating: .good, parameters: parameters).newInterval, 20.0 / 1440, accuracy: 0.000001)
        XCTAssertEqual(Scheduler.nextIntervalDescription(card: card, rating: .easy, now: fixture.now, defaults: fixture.defaults), "1mo")
        XCTAssertTrue(Scheduler.applyReview(card: card, rating: .easy, timeTakenMs: 1, context: fixture.context, now: fixture.now, defaults: fixture.defaults))
        XCTAssertEqual(card.interval, 30)
        XCTAssertEqual(card.dueDate.timeIntervalSince(fixture.now), 30 * 86400, accuracy: 0.001)
        card.state = .learning
        card.learningStep = 1
        XCTAssertEqual(SM2Algorithm.review(card: card, rating: .good, parameters: parameters).newInterval, 7)
        XCTAssertEqual(SM2SchedulingParameters.parseLearningSteps("30s 2m 1h 1d 5"), [0.5, 2, 60, 1440, 5])
        XCTAssertNil(SM2SchedulingParameters.parseLearningSteps("1m invalid"))
        XCTAssertNil(SM2SchedulingParameters.parseLearningSteps("nan"))
        XCTAssertNil(SM2SchedulingParameters.parseLearningSteps("0m"))
    }

    @MainActor
    func testFailedSaveDoesNotAdvanceSchedulingOrCreateAReview() throws {
        let fixture = try SchedulingFixture()
        defer { fixture.cleanUp() }
        let card = fixture.card("Unsaved")
        try fixture.context.save()
        let originalDue = card.dueDate
        let originalModified = card.modifiedAt
        let saved = Scheduler.applyReview(card: card, rating: .easy, timeTakenMs: 1, context: fixture.context, now: fixture.now, defaults: fixture.defaults, save: { _ in throw SchedulingTestError.simulatedSaveFailure })
        XCTAssertFalse(saved)
        XCTAssertEqual(card.state, .new)
        XCTAssertEqual(card.interval, 0)
        XCTAssertEqual(card.dueDate, originalDue)
        XCTAssertEqual(card.modifiedAt, originalModified)
        XCTAssertTrue(card.reviewLogs.isEmpty)
    }

    @MainActor
    func testFailedUndoKeepsSavedReviewAndCanBeRetried() throws {
        let fixture = try SchedulingFixture()
        defer { fixture.cleanUp() }
        let card = fixture.card("Undo")
        XCTAssertTrue(Scheduler.applyReview(card: card, rating: .easy, timeTakenMs: 1, context: fixture.context, now: fixture.now, defaults: fixture.defaults))
        let savedDue = card.dueDate
        var saves = 0
        let undone = Scheduler.undoLastReview(card: card, context: fixture.context, now: fixture.now, save: { context in
            saves += 1
            if saves == 2 { throw SchedulingTestError.simulatedSaveFailure }
            try context.save()
        })
        XCTAssertFalse(undone)
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.dueDate, savedDue)
        XCTAssertEqual(card.reviewLogs.count, 1)
        XCTAssertTrue(Scheduler.undoLastReview(card: card, context: fixture.context, now: fixture.now))
        XCTAssertEqual(card.state, .new)
        XCTAssertTrue(card.reviewLogs.isEmpty)
    }

    @MainActor
    func testMatureSM2ImportIsNotTreatedAsANewFSRSCard() throws {
        let fixture = try SchedulingFixture(useFSRS: true)
        defer { fixture.cleanUp() }
        let card = fixture.card("Imported", state: .review, dueDate: fixture.now.addingTimeInterval(-2 * 86400))
        card.interval = 30
        card.repetitions = 5
        card.lapseCount = 2
        card.lastReviewDate = fixture.now.addingTimeInterval(-32 * 86400)
        let result = FSRSAlgorithm.review(card: card, rating: .good, now: fixture.now)
        XCTAssertEqual(result.newState, .review)
        XCTAssertEqual(result.newReps, 6)
        XCTAssertEqual(result.newLapses, 2)
        XCTAssertGreaterThanOrEqual(result.newInterval, 1)
        XCTAssertTrue(card.reviewLogs.isEmpty)
        XCTAssertTrue(Scheduler.applyReview(card: card, rating: .good, timeTakenMs: 1, context: fixture.context, now: fixture.now, defaults: fixture.defaults))
        XCTAssertEqual(card.state, .review)
        XCTAssertEqual(card.repetitions, 6)
        XCTAssertEqual(card.reviewLogs.count, 1)
        XCTAssertEqual(card.reviewLogs.first?.cardStateBefore, CardState.review.rawValue)
    }
}

private enum SchedulingTestError: Error { case simulatedSaveFailure }

@MainActor
private final class SchedulingFixture {
    let container: ModelContainer
    let context: ModelContext
    let deck: Deck
    let defaults: UserDefaults
    let suiteName = "RecallRx.SchedulingTests.\(UUID().uuidString)"
    let now = Date(timeIntervalSince1970: 1_772_884_800) // Fixed reference; no wall-clock dependence.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    init(newLimit: Int = 20, reviewLimit: Int = 200, autoAdvance: Bool = true, useFSRS: Bool = false) throws {
        let schema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(useFSRS, forKey: "useFSRS")
        defaults.set(false, forKey: "enableLoadBalancer")
        defaults.set(autoAdvance, forKey: "autoAdvance")
        deck = Deck(name: "Regression", newCardsPerDay: newLimit, reviewsPerDay: reviewLimit)
        context.insert(deck)
    }

    func card(_ name: String, createdAt: Date? = nil, state: CardState = .new, dueDate: Date? = nil) -> Card {
        let card = Card(front: name, back: "Answer", deck: deck, createdAt: createdAt ?? now.addingTimeInterval(-60), modifiedAt: now.addingTimeInterval(-60), dueDate: dueDate ?? now.addingTimeInterval(-1), stateRaw: state.rawValue)
        context.insert(card)
        if !deck.cards.contains(where: { $0.id == card.id }) { deck.cards.append(card) }
        return card
    }

    func log(on card: Card, at date: Date, before state: CardState) {
        let log = ReviewLog(card: card, rating: Rating.good.rawValue, reviewDate: date, cardStateBefore: state.rawValue, cardStateAfter: card.stateRaw)
        context.insert(log)
        if !card.reviewLogs.contains(where: { $0.id == log.id }) { card.reviewLogs.append(log) }
    }

    func session() -> StudyViewModel {
        StudyViewModel(deck: deck, modelContext: context, now: { self.now }, calendar: calendar, defaults: defaults)
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }
}
