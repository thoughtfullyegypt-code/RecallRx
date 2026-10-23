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
        let suiteName = "RecallRx.SyncTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return store
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

    func testFailedRemoteUpdatePreservesLatestSavedModelsAndJournal() throws {
        enum Failure: Error { case diskFull }
        let container = try store()
        let context = container.mainContext
        let deck = Deck(name: "Seed deck", newCardsPerDay: 1)
        let card = Card(front: "Seed prompt", back: "Seed answer", deck: deck, interval: 1)
        context.insert(deck)
        context.insert(card)
        try context.save()

        let savedDate = Date(timeIntervalSince1970: 1_700_000_000)
        deck.name = "Original deck"
        deck.newCardsPerDay = 7
        deck.modifiedAt = savedDate
        card.front = "Original prompt"
        card.back = "Original answer"
        card.interval = 12
        card.modifiedAt = savedDate
        try context.save()

        let isolated = defaults()
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false, persistChanges: { _ in throw Failure.diskFull })
        try sync.captureLocalDeletions(context: context)
        let originalJournal = try XCTUnwrap(isolated.data(forKey: "recallrx_sync_journal_v1"))
        let remoteDeck = sync.record(for: deck)
        remoteDeck["name"] = "Remote deck" as NSString
        remoteDeck["newCardsPerDay"] = 99 as NSNumber
        remoteDeck["modifiedAt"] = savedDate.addingTimeInterval(60) as NSDate
        let remoteCard = sync.record(for: card)
        remoteCard["front"] = "Remote prompt" as NSString
        remoteCard["back"] = "Remote answer" as NSString
        remoteCard["interval"] = 99 as NSNumber
        remoteCard["modifiedAt"] = savedDate.addingTimeInterval(60) as NSDate

        XCTAssertThrowsError(try sync.applyRemoteChanges(records: [remoteCard, remoteDeck], context: context))

        func assertOriginalValues(card: Card, deck: Deck, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(deck.name, "Original deck", file: file, line: line)
            XCTAssertEqual(deck.newCardsPerDay, 7, file: file, line: line)
            XCTAssertEqual(deck.modifiedAt, savedDate, file: file, line: line)
            XCTAssertEqual(card.front, "Original prompt", file: file, line: line)
            XCTAssertEqual(card.back, "Original answer", file: file, line: line)
            XCTAssertEqual(card.interval, 12, file: file, line: line)
            XCTAssertEqual(card.modifiedAt, savedDate, file: file, line: line)
            XCTAssertEqual(card.deck?.id, deck.id, file: file, line: line)
        }
        assertOriginalValues(card: card, deck: deck)
        assertOriginalValues(card: try XCTUnwrap(context.fetch(FetchDescriptor<Card>()).first),
                             deck: try XCTUnwrap(context.fetch(FetchDescriptor<Deck>()).first))
        let freshContext = ModelContext(container)
        assertOriginalValues(card: try XCTUnwrap(freshContext.fetch(FetchDescriptor<Card>()).first),
                             deck: try XCTUnwrap(freshContext.fetch(FetchDescriptor<Deck>()).first))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(isolated.data(forKey: "recallrx_sync_journal_v1"), originalJournal)
    }

    func testFailedRemoteMoveAndReviewInsertionPreserveSavedGraphAndJournal() throws {
        enum Failure: Error { case diskFull }
        let container = try store()
        let context = container.mainContext
        let sourceDeck = Deck(name: "Source")
        let targetDeck = Deck(name: "Target")
        let card = Card(front: "Seed prompt", back: "Answer", deck: sourceDeck)
        let targetCard = Card(front: "Keep in target", back: "Answer", deck: targetDeck)
        let originalLog = ReviewLog(card: card, rating: 2)
        context.insert(sourceDeck)
        context.insert(targetDeck)
        context.insert(card)
        context.insert(targetCard)
        context.insert(originalLog)
        try context.save()
        let savedDate = Date(timeIntervalSince1970: 1_700_000_000)
        card.front = "Original prompt"
        card.interval = 12
        card.modifiedAt = savedDate
        try context.save()

        let isolated = defaults()
        var persistAttempts = 0
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false, persistChanges: { _ in
            persistAttempts += 1
            throw Failure.diskFull
        })
        try sync.captureLocalDeletions(context: context)
        let originalJournal = try XCTUnwrap(isolated.data(forKey: "recallrx_sync_journal_v1"))
        let remoteCard = sync.record(for: card)
        remoteCard["deckID"] = targetDeck.id.uuidString as NSString
        remoteCard["front"] = "Remote prompt" as NSString
        remoteCard["modifiedAt"] = savedDate.addingTimeInterval(60) as NSDate
        let remoteLog = CKRecord(recordType: "ReviewLog", recordID: CKRecord.ID(recordName: UUID().uuidString))
        remoteLog["cardID"] = card.id.uuidString as NSString
        remoteLog["rating"] = 3 as NSNumber

        XCTAssertThrowsError(try sync.applyRemoteChanges(records: [remoteLog, remoteCard], context: context)) {
            XCTAssertTrue($0 is Failure)
        }
        XCTAssertEqual(persistAttempts, 1)
        XCTAssertEqual(card.front, "Original prompt")
        XCTAssertEqual(card.interval, 12)
        XCTAssertEqual(card.modifiedAt, savedDate)
        XCTAssertTrue(card.deck === sourceDeck)
        XCTAssertEqual(sourceDeck.cards.map(\.id), [card.id])
        XCTAssertTrue(sourceDeck.cards.first === card)
        XCTAssertEqual(targetDeck.cards.map(\.id), [targetCard.id])
        XCTAssertTrue(targetDeck.cards.first === targetCard)
        XCTAssertTrue(targetCard.deck === targetDeck)
        XCTAssertEqual(card.reviewLogs.map(\.id), [originalLog.id])
        XCTAssertTrue(card.reviewLogs.first === originalLog)
        XCTAssertTrue(originalLog.card === card)
        XCTAssertFalse(context.hasChanges)

        let freshContext = ModelContext(container)
        let decks = try freshContext.fetch(FetchDescriptor<Deck>())
        let cards = try freshContext.fetch(FetchDescriptor<Card>())
        let logs = try freshContext.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(decks.count, 2)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(logs.map(\.id), [originalLog.id])
        let persistedSource = try XCTUnwrap(decks.first { $0.id == sourceDeck.id })
        let persistedTarget = try XCTUnwrap(decks.first { $0.id == targetDeck.id })
        let persistedCard = try XCTUnwrap(cards.first { $0.id == card.id })
        XCTAssertEqual(persistedCard.front, "Original prompt")
        XCTAssertEqual(persistedCard.interval, 12)
        XCTAssertEqual(persistedCard.modifiedAt, savedDate)
        XCTAssertEqual(persistedCard.deck?.id, sourceDeck.id)
        XCTAssertEqual(persistedSource.cards.map(\.id), [card.id])
        XCTAssertEqual(persistedTarget.cards.map(\.id), [targetCard.id])
        XCTAssertEqual(persistedCard.reviewLogs.map(\.id), [originalLog.id])
        XCTAssertEqual(logs.first?.card?.id, card.id)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(isolated.data(forKey: "recallrx_sync_journal_v1"), originalJournal)
    }

    func testFailedRemoteDeckDeletionPreservesSavedCascadeGraphAndJournal() throws {
        enum Failure: Error { case diskFull }
        let container = try store()
        let context = container.mainContext
        let deck = Deck(name: "Seed deck")
        let card = Card(front: "Seed prompt", back: "Answer", deck: deck)
        let log = ReviewLog(card: card, rating: 1)
        context.insert(deck)
        context.insert(card)
        context.insert(log)
        try context.save()
        let savedDate = Date(timeIntervalSince1970: 1_700_000_000)
        deck.name = "Original deck"
        deck.modifiedAt = savedDate
        card.front = "Original prompt"
        card.modifiedAt = savedDate
        log.rating = 2
        try context.save()

        let isolated = defaults()
        var persistAttempts = 0
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false, persistChanges: { _ in
            persistAttempts += 1
            throw Failure.diskFull
        })
        try sync.captureLocalDeletions(context: context)
        let originalJournal = try XCTUnwrap(isolated.data(forKey: "recallrx_sync_journal_v1"))
        let deckRecordID = CKRecord.ID(recordName: "deck-" + deck.id.uuidString)
        XCTAssertThrowsError(try sync.applyRemoteChanges(records: [], deletions: [(deckRecordID, "Deck")], context: context)) {
            XCTAssertTrue($0 is Failure)
        }
        XCTAssertEqual(persistAttempts, 1)
        XCTAssertFalse(deck.isDeleted)
        XCTAssertFalse(card.isDeleted)
        XCTAssertFalse(log.isDeleted)
        XCTAssertEqual(deck.name, "Original deck")
        XCTAssertEqual(deck.modifiedAt, savedDate)
        XCTAssertEqual(card.front, "Original prompt")
        XCTAssertEqual(card.modifiedAt, savedDate)
        XCTAssertEqual(log.rating, 2)
        XCTAssertEqual(deck.cards.map(\.id), [card.id])
        XCTAssertTrue(deck.cards.first === card)
        XCTAssertTrue(card.deck === deck)
        XCTAssertEqual(card.reviewLogs.map(\.id), [log.id])
        XCTAssertTrue(card.reviewLogs.first === log)
        XCTAssertTrue(log.card === card)
        XCTAssertFalse(context.hasChanges)

        let freshContext = ModelContext(container)
        let decks = try freshContext.fetch(FetchDescriptor<Deck>())
        let cards = try freshContext.fetch(FetchDescriptor<Card>())
        let logs = try freshContext.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(decks.map(\.id), [deck.id])
        XCTAssertEqual(cards.map(\.id), [card.id])
        XCTAssertEqual(logs.map(\.id), [log.id])
        let persistedDeck = try XCTUnwrap(decks.first)
        let persistedCard = try XCTUnwrap(cards.first)
        let persistedLog = try XCTUnwrap(logs.first)
        XCTAssertEqual(persistedDeck.name, "Original deck")
        XCTAssertEqual(persistedDeck.modifiedAt, savedDate)
        XCTAssertEqual(persistedCard.front, "Original prompt")
        XCTAssertEqual(persistedCard.modifiedAt, savedDate)
        XCTAssertEqual(persistedLog.rating, 2)
        XCTAssertEqual(persistedDeck.cards.map(\.id), [card.id])
        XCTAssertEqual(persistedCard.deck?.id, deck.id)
        XCTAssertEqual(persistedCard.reviewLogs.map(\.id), [log.id])
        XCTAssertEqual(persistedLog.card?.id, card.id)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(isolated.data(forKey: "recallrx_sync_journal_v1"), originalJournal)
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
    func testOrphanedCardAndReviewRemainValidAcrossDevices() throws {
        let source = try store()
        let card = Card(front: "Unfiled", back: "Answer")
        let orphanLog = ReviewLog(rating: 2)
        source.mainContext.insert(card)
        source.mainContext.insert(orphanLog)
        try source.mainContext.save()
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        let target = try store()
        try sync.applyRemoteChanges(records: [sync.record(for: orphanLog), sync.record(for: card)], context: target.mainContext)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Card>()), 1)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 1)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Deck>()), 0)
        XCTAssertNil(try target.mainContext.fetch(FetchDescriptor<ReviewLog>()).first?.card)
    }

    func testExplicitRestoreCanRevivePreviouslyDeletedIdentity() throws {
        let container = try store()
        let card = Card(front: "Restore me", back: "Answer")
        let id = card.id
        container.mainContext.insert(card)
        try container.mainContext.save()
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        try sync.captureLocalDeletions(context: container.mainContext)
        container.mainContext.delete(card)
        try container.mainContext.save()
        try sync.captureLocalDeletions(context: container.mainContext)
        container.mainContext.insert(Card(id: id, front: "Restored", back: "Answer"))
        try container.mainContext.save()
        try sync.markRestoredLibrary(context: container.mainContext)
        let tombstone = CKRecord(recordType: "Deletion", recordID: CKRecord.ID(recordName: "deleted-" + id.uuidString))
        tombstone["recordName"] = id.uuidString as NSString
        tombstone["entityType"] = "Card" as NSString
        try sync.applyRemoteChanges(records: [tombstone], context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Card>()).first?.front, "Restored")
    }

    func testDeletingRestoredCardBeforeSyncCancelsRestorationIntent() throws {
        let container = try store()
        let card = Card(front: "Restored then deleted", back: "Answer")
        container.mainContext.insert(card)
        try container.mainContext.save()
        let isolated = defaults()
        let sync = CloudSyncManager(defaults: isolated, monitorNetwork: false)
        try sync.markRestoredLibrary(context: container.mainContext)
        let name = card.id.uuidString
        container.mainContext.delete(card)
        try container.mainContext.save()
        try sync.captureLocalDeletions(context: container.mainContext)
        let journal = try JSONDecoder().decode(SyncJournal.self, from: XCTUnwrap(isolated.data(forKey: "recallrx_sync_journal_v1")))
        XCTAssertFalse(journal.restoredRecords.contains(name))
        XCTAssertEqual(journal.pendingDeletions[name], "Card")
        XCTAssertEqual(journal.tombstones[name], "Card")
    }

    func testRestorationWinsOverEarlierDeletionInTheSamePulledBatch() throws {
        let container = try store()
        let id = UUID()
        let record = CKRecord(recordType: "Card", recordID: CKRecord.ID(recordName: id.uuidString))
        record["version"] = 2 as NSNumber
        record["front"] = "Restored on another device" as NSString
        let markerID = CKRecord.ID(recordName: "deleted-" + id.uuidString)
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        try sync.applyRemoteChanges(records: [record],
            deletions: [(CKRecord.ID(recordName: id.uuidString), "Card"), (markerID, "Deletion")],
            context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 1)
    }

    func testDeckDeletionSuppressesLateReviewForCascadedCard() throws {
        let container = try store()
        let deck = Deck(name: "Deleted deck")
        let card = Card(front: "Q", back: "A", deck: deck)
        container.mainContext.insert(deck)
        container.mainContext.insert(card)
        try container.mainContext.save()
        let marker = CKRecord(recordType: "Deletion", recordID: CKRecord.ID(recordName: "deleted-deck-" + deck.id.uuidString))
        marker["recordName"] = ("deck-" + deck.id.uuidString) as NSString
        marker["entityType"] = "Deck" as NSString
        let lateReview = CKRecord(recordType: "ReviewLog", recordID: CKRecord.ID(recordName: UUID().uuidString))
        lateReview["cardID"] = card.id.uuidString as NSString
        let sync = CloudSyncManager(defaults: defaults(), monitorNetwork: false)
        try sync.applyRemoteChanges(records: [lateReview, marker], context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Deck>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ReviewLog>()), 0)
    }

}
