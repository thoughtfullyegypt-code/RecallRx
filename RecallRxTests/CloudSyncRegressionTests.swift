import CloudKit
import SwiftData
import XCTest
@testable import RecallRx

@MainActor
final class CloudSyncRegressionTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let schema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "RecallRx.SyncTests.\(UUID().uuidString)")!
    }

    func testReviewArrivingBeforeCardIsAppliedAfterParentAndDeduplicated() throws {
        let source = try store()
        let deck = Deck(name: "Medicine")
        let card = Card(front: "Prompt", back: "Answer", deck: deck)
        let log = ReviewLog(card: card, rating: 2)
        source.mainContext.insert(deck)
        source.mainContext.insert(card)
        source.mainContext.insert(log)
        try source.mainContext.save()
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        let records = [sync.record(for: log), sync.record(for: card), sync.record(for: deck)]
        let target = try store()
        try sync.applyRemoteChanges(records: records, context: target.mainContext)
        try sync.applyRemoteChanges(records: records, context: target.mainContext)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Card>()), 1)
        let imported = try target.mainContext.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.card?.id, card.id)
    }

    func testMissingParentFailsWithoutAdvancingJournalOrLosingLibrary() throws {
        let container = try store()
        let deck = Deck(name: "Preserve me")
        container.mainContext.insert(deck)
        try container.mainContext.save()
        let isolated = defaults()
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false)
        let record = CKRecord(recordType: "ReviewLog", recordID: CKRecord.ID(recordName: UUID().uuidString))
        record["cardID"] = UUID().uuidString as NSString
        XCTAssertThrowsError(try sync.applyRemoteChanges(records: [record], context: container.mainContext))
        XCTAssertNil(isolated.data(forKey: "recallrx_sync_journal_v1"))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Deck>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 0)
    }

    func testFailedSaveRollsBackRemoteInsertionAndDoesNotCheckpoint() throws {
        enum Failure: Error { case diskFull }
        let container = try store()
        let isolated = defaults()
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false, persistChanges: { _ in throw Failure.diskFull })
        let record = CKRecord(recordType: "Card", recordID: CKRecord.ID(recordName: UUID().uuidString))
        record["front"] = "Remote" as NSString
        XCTAssertThrowsError(try sync.applyRemoteChanges(records: [record], context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Deck>()), 0)
        XCTAssertNil(isolated.data(forKey: "recallrx_sync_journal_v1"))
    }

    func testOfflineDeletionSurvivesManagerRestartAndSuppressesStaleRemoteCard() throws {
        let container = try store()
        let deck = Deck(name: "Deck")
        let card = Card(front: "Delete", back: "Me", deck: deck)
        container.mainContext.insert(deck)
        container.mainContext.insert(card)
        try container.mainContext.save()
        let isolated = defaults()
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false)
        let stale = sync.record(for: card)
        try sync.captureLocalDeletions(context: container.mainContext)
        container.mainContext.delete(card)
        try container.mainContext.save()
        let restarted = CloudSyncManager(defaults: isolated, monitorNetwork: false)
        try restarted.captureLocalDeletions(context: container.mainContext)
        try restarted.applyRemoteChanges(records: [stale], context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 0)
        let journal = try JSONDecoder().decode(SyncJournal.self, from: XCTUnwrap(isolated.data(forKey: "recallrx_sync_journal_v1")))
        XCTAssertNotNil(journal.pendingDeletions[stale.recordID.recordName])
    }

    func testRemoteDeletionRemovesLocalCardAndReviewHistory() throws {
        let container = try store()
        let card = Card(front: "Q", back: "A")
        container.mainContext.insert(card)
        container.mainContext.insert(ReviewLog(card: card, rating: 2))
        try container.mainContext.save()
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        try sync.applyRemoteChanges(records: [], deletions: [(CKRecord.ID(recordName: card.id.uuidString), "Card")], context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 0)
    }

    func testFullCardAndDeckStateRoundTrip() throws {
        let source = try store()
        let deck = Deck(name: "Cardiology", newCardsPerDay: 7, reviewsPerDay: 35)
        let card = Card(front: "{{c1::Answer}}", back: "", deck: deck, noteTypeRaw: NoteType.medical.rawValue,
                        isSuspended: true, isBuried: true, interval: 30,
                        lastReviewDate: Date(timeIntervalSince1970: 1_700_000_000), stateRaw: "review", learningStep: 2,
                        clinicalPearls: "Pearl", fsrsStability: 18, fsrsDifficulty: 4, fsrsReps: 9, fsrsLapses: 2)
        card.buriedUntil = Date().addingTimeInterval(3600)
        source.mainContext.insert(deck)
        source.mainContext.insert(card)
        try source.mainContext.save()
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        let target = try store()
        try sync.applyRemoteChanges(records: [sync.record(for: card), sync.record(for: deck)], context: target.mainContext)
        let restored = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Card>()).first)
        XCTAssertEqual(restored.id, card.id)
        XCTAssertEqual(restored.noteType, .medical)
        XCTAssertEqual(restored.lastReviewDate, card.lastReviewDate)
        XCTAssertEqual(restored.buriedUntil, card.buriedUntil)
        XCTAssertEqual(restored.fsrsReps, 9)
        XCTAssertEqual(restored.learningStep, 2)
        XCTAssertEqual(restored.clinicalPearls, "Pearl")
        XCTAssertTrue(restored.isSuspended)
        XCTAssertEqual(restored.deck?.newCardsPerDay, 7)
    }
}
