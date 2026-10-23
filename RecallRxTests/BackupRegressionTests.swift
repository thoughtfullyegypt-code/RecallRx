import Foundation
import SwiftData
import XCTest
@testable import RecallRx

@MainActor
final class BackupRegressionTests: XCTestCase {
    func testCorruptBackupDoesNotDeleteLibraryOrMedia() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let paths = try makeDirectories()
        let deck = Deck(name: "Keep this deck")
        context.insert(deck)
        try context.save()
        let image = paths.media.appendingPathComponent("image.png")
        try Data([1, 2, 3]).write(to: image)
        let corrupt = paths.root.appendingPathComponent("corrupt.json")
        try Data("{\"formatVersion\":2,\"decks\":[]}".utf8).write(to: corrupt)

        let manager = BackupManager(backupsDirectoryURL: paths.backups, mediaDirectoryURL: paths.media)
        XCTAssertThrowsError(try manager.restoreSnapshot(from: corrupt, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).map(\.id), [deck.id])
        XCTAssertEqual(try Data(contentsOf: image), Data([1, 2, 3]))
        XCTAssertTrue(manager.listSnapshots().isEmpty)
    }

    func testSnapshotRoundTripPreservesAllModelFieldsAndMedia() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let paths = try makeDirectories()
        let time = Date(timeIntervalSinceReferenceDate: 800_000_000.12345)
        let parent = Deck(name: "Medicine", createdAt: time, modifiedAt: time, isCollapsed: true, newCardsPerDay: 7, reviewsPerDay: 77)
        let child = Deck(name: "Medicine::Cardiology", descriptionText: "Details", createdAt: time, modifiedAt: time, parentDeckID: parent.id, newCardsPerDay: 9, reviewsPerDay: 99)
        context.insert(parent)
        context.insert(child)
        let card = Card(
            front: "{{c1::Valve}} <img src=\"diagrams/heart.png\">", back: "Answer",
            deck: child, tags: ["cardiology"], noteTypeRaw: NoteType.cloze.rawValue,
            createdAt: time, modifiedAt: time, isSuspended: true, isBuried: true,
            buriedUntil: time.addingTimeInterval(86_400), lapseCount: 3,
            interval: 14.5, easeFactor: 2.3, repetitions: 12,
            dueDate: time.addingTimeInterval(1_000), lastReviewDate: time,
            stateRaw: CardState.learning.rawValue, learningStep: 1, queueRaw: "learning",
            extra: "Extra", firstAid: "Outline", sketchy: "Visual", pathoma: "Pathology", clinicalPearls: "Pearl",
            fsrsStability: 12.3, fsrsDifficulty: 5.4, fsrsReps: 12, fsrsLapses: 3
        )
        context.insert(card)
        let log = ReviewLog(
            card: card, rating: 3, reviewDate: time, timeTakenMs: 2345,
            intervalBefore: 3.5, intervalAfter: 14.5, easeFactorBefore: 2.4,
            easeFactorAfter: 2.3, cardStateBefore: "new", cardStateAfter: "learning"
        )
        context.insert(log)
        context.insert(Tag(name: "cardiology", createdAt: time))
        // Nullable relationships are legitimate persisted state and must not disappear.
        context.insert(Card(front: "Unfiled card", createdAt: time, modifiedAt: time))
        context.insert(ReviewLog(rating: 2, reviewDate: time))
        try context.save()
        let media = MediaManager(mediaDirectoryURL: paths.media)
        try media.saveMedia(data: Data([0, 127, 255]), named: "diagrams/heart.png")
        try media.saveMedia(data: Data([7, 8, 9]), named: "heartbeat.mp3")
        let expected = try BackupArchive.capture(context: context, mediaDirectoryURL: paths.media)
        let manager = BackupManager(backupsDirectoryURL: paths.backups, mediaDirectoryURL: paths.media)
        let snapshot = try manager.createSnapshot(context: context)

        card.front = "Changed"
        card.lastReviewDate = nil
        card.isSuspended = false
        child.newCardsPerDay = 50
        try context.save()
        try media.saveMedia(data: Data([99]), named: "diagrams/heart.png")
        try media.saveMedia(data: Data([88]), named: "extra.png")

        try manager.restoreSnapshot(from: snapshot, context: context)
        let actual = try BackupArchive.capture(context: context, mediaDirectoryURL: paths.media)
        XCTAssertEqual(actual.decks.sorted { $0.id.uuidString < $1.id.uuidString }, expected.decks.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(actual.cards.sorted { $0.id.uuidString < $1.id.uuidString }, expected.cards.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(actual.reviewLogs.sorted { $0.id.uuidString < $1.id.uuidString }, expected.reviewLogs.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(actual.tags.sorted { $0.id.uuidString < $1.id.uuidString }, expected.tags.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(actual.media, expected.media)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.media.appendingPathComponent("extra.png").path))
    }

    func testFailedReplacementSaveRollsBackModelsAndMedia() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let paths = try makeDirectories()
        let deck = Deck(name: "Original snapshot")
        context.insert(deck)
        let card = Card(front: "Snapshot question", deck: deck)
        context.insert(card)
        try context.save()
        let image = paths.media.appendingPathComponent("same.png")
        try Data([1]).write(to: image)
        let manager = BackupManager(backupsDirectoryURL: paths.backups, mediaDirectoryURL: paths.media)
        let snapshot = try manager.createSnapshot(context: context)
        deck.name = "Current library"
        card.front = "Current question"
        let extra = Deck(name: "New deck after snapshot")
        context.insert(extra)
        try context.save()
        try Data([2, 3]).write(to: image)
        let expectedDecks = try context.fetch(FetchDescriptor<Deck>()).map(BackupDeckRecord.init)
        let expectedCards = try context.fetch(FetchDescriptor<Card>()).map(BackupCardRecord.init)
        let failing = BackupManager(
            backupsDirectoryURL: paths.backups,
            mediaDirectoryURL: paths.media,
            saveContext: { _ in throw CocoaError(.fileWriteOutOfSpace) }
        )

        XCTAssertThrowsError(try failing.restoreSnapshot(from: snapshot, context: context))
        let reloaded = ModelContext(container)
        XCTAssertEqual(try reloaded.fetch(FetchDescriptor<Deck>()).map(BackupDeckRecord.init).sorted { $0.id.uuidString < $1.id.uuidString }, expectedDecks.sorted { $0.id.uuidString < $1.id.uuidString })
        XCTAssertEqual(try reloaded.fetch(FetchDescriptor<Card>()).map(BackupCardRecord.init), expectedCards)
        XCTAssertEqual(try Data(contentsOf: image), Data([2, 3]))
        XCTAssertFalse(context.hasChanges)
    }

    func testRestoreRequiresSuccessfulSafetyBackup() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let paths = try makeDirectories()
        let deck = Deck(name: "Keep")
        context.insert(deck)
        try context.save()
        let manager = BackupManager(backupsDirectoryURL: paths.backups, mediaDirectoryURL: paths.media)
        let snapshot = try manager.createSnapshot(context: context)
        let blocked = paths.root.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: blocked)
        let failing = BackupManager(backupsDirectoryURL: blocked, mediaDirectoryURL: paths.media)
        XCTAssertThrowsError(try failing.restoreSnapshot(from: snapshot, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).map(\.id), [deck.id])
    }

    func testUnsafeMediaAndDuplicateModelIDsAreRejectedBeforeReplacement() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let paths = try makeDirectories()
        let deck = Deck(name: "Keep")
        context.insert(deck)
        try context.save()
        let data = try ImportExportManager.exportAllDecks(context: context, mediaDirectoryURL: paths.media)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var unsafe = original
        unsafe["media"] = [["relativePath": "../escape.png", "data": Data([1]).base64EncodedString()]]
        let unsafeURL = paths.root.appendingPathComponent("unsafe.json")
        try JSONSerialization.data(withJSONObject: unsafe).write(to: unsafeURL)
        let manager = BackupManager(backupsDirectoryURL: paths.backups, mediaDirectoryURL: paths.media)
        XCTAssertThrowsError(try manager.restoreSnapshot(from: unsafeURL, context: context))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.root.appendingPathComponent("escape.png").path))

        var duplicate = original
        let records = try XCTUnwrap(original["decks"] as? [[String: Any]])
        duplicate["decks"] = records + records
        let duplicateURL = paths.root.appendingPathComponent("duplicate.json")
        try JSONSerialization.data(withJSONObject: duplicate).write(to: duplicateURL)
        XCTAssertThrowsError(try manager.restoreSnapshot(from: duplicateURL, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).map(\.id), [deck.id])
    }

    func testLegacyRestoreRetainsExistingMedia() throws {
        let container = try makeContainer()
        let paths = try makeDirectories()
        let image = paths.media.appendingPathComponent("legacy.png")
        try Data([5, 6]).write(to: image)
        let legacy = paths.root.appendingPathComponent("legacy.json")
        try Data("[{\"deckName\":\"Legacy deck\",\"cards\":[{\"front\":\"Legacy question\",\"back\":\"Answer\"}]}]".utf8).write(to: legacy)
        let manager = BackupManager(backupsDirectoryURL: paths.backups, mediaDirectoryURL: paths.media)
        try manager.restoreSnapshot(from: legacy, context: container.mainContext)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Deck>()).first?.name, "Legacy deck")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Card>()).first?.front, "Legacy question")
        XCTAssertEqual(try Data(contentsOf: image), Data([5, 6]))
    }

    func testPortableExportImportsMediaAndRejectsDuplicateIdentities() throws {
        let source = try makeContainer()
        let destination = try makeContainer()
        let sourcePaths = try makeDirectories()
        let destinationPaths = try makeDirectories()
        let deck = Deck(name: "Portable")
        source.mainContext.insert(deck)
        source.mainContext.insert(Card(front: "<img src=\"image.png\">", deck: deck))
        try source.mainContext.save()
        try Data([1, 4, 9]).write(to: sourcePaths.media.appendingPathComponent("image.png"))
        let data = try ImportExportManager.exportAllDecks(context: source.mainContext, mediaDirectoryURL: sourcePaths.media)
        _ = try ImportExportManager.importAllDecks(from: data, context: destination.mainContext, mediaDirectoryURL: destinationPaths.media)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Deck>()).map(\.id), [deck.id])
        XCTAssertEqual(try Data(contentsOf: destinationPaths.media.appendingPathComponent("image.png")), Data([1, 4, 9]))
        XCTAssertThrowsError(try ImportExportManager.importAllDecks(from: data, context: destination.mainContext, mediaDirectoryURL: destinationPaths.media))
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Deck>()), 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    private func makeDirectories() throws -> (root: URL, backups: URL, media: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecallRx-BackupTests-\(UUID().uuidString)", isDirectory: true)
        let media = root.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, root.appendingPathComponent("Backups", isDirectory: true), media)
    }
}
