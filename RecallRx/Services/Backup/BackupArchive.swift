import Foundation
import SwiftData

/// Version 2 stores model identity, scheduler state, and media together.
/// A nil media collection is reserved for legacy deck JSON, which never contained assets.
struct BackupArchive: Codable {
    let formatVersion: Int
    let createdAt: Date
    let decks: [BackupDeckRecord]
    let cards: [BackupCardRecord]
    let reviewLogs: [BackupReviewRecord]
    let tags: [BackupTagRecord]
    let media: [BackupMediaRecord]?

    static func capture(context: ModelContext, mediaDirectoryURL: URL) throws -> BackupArchive {
        let archive = BackupArchive(
            formatVersion: 2,
            createdAt: Date(),
            decks: try context.fetch(FetchDescriptor<Deck>()).map(BackupDeckRecord.init),
            cards: try context.fetch(FetchDescriptor<Card>()).map(BackupCardRecord.init),
            reviewLogs: try context.fetch(FetchDescriptor<ReviewLog>()).map(BackupReviewRecord.init),
            tags: try context.fetch(FetchDescriptor<Tag>()).map(BackupTagRecord.init),
            media: try BackupMediaStaging.readMedia(in: mediaDirectoryURL)
        )
        try archive.validate()
        return archive
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Deferred dates preserve subsecond review timestamps without ISO-8601 truncation.
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        guard !data.isEmpty else { throw ImportError.emptyFile }
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["formatVersion"] != nil {
            let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
            guard archive.media != nil else {
                throw BackupArchiveError.invalid("the media collection is missing")
            }
            try archive.validate()
            return archive
        }
        return try legacyArchive(from: data)
    }

    func validate() throws {
        guard formatVersion == 2 else { throw BackupArchiveError.unsupportedVersion(formatVersion) }
        try Self.requireUnique(decks.map(\.id), kind: "deck")
        try Self.requireUnique(cards.map(\.id), kind: "card")
        try Self.requireUnique(reviewLogs.map(\.id), kind: "review")
        try Self.requireUnique(tags.map(\.id), kind: "tag")
        let deckIDs = Set(decks.map(\.id))
        let cardIDs = Set(cards.map(\.id))
        let parents = Dictionary(uniqueKeysWithValues: decks.compactMap { deck in
            deck.parentDeckID.map { (deck.id, $0) }
        })
        for deck in decks {
            guard deck.newCardsPerDay >= 0, deck.reviewsPerDay >= 0 else {
                throw BackupArchiveError.invalid("negative daily limits")
            }
            if let parentID = deck.parentDeckID, !deckIDs.contains(parentID) {
                throw BackupArchiveError.invalid("a parent deck is missing")
            }
            var visited: Set<UUID> = [deck.id]
            var parent = deck.parentDeckID
            while let id = parent {
                guard visited.insert(id).inserted else {
                    throw BackupArchiveError.invalid("deck hierarchy contains a cycle")
                }
                parent = parents[id]
            }
            try Self.validateDates([deck.createdAt, deck.modifiedAt])
        }
        for card in cards {
            if let id = card.deckID, !deckIDs.contains(id) {
                throw BackupArchiveError.invalid("a card's deck is missing")
            }
            guard CardState(rawValue: card.stateRaw) != nil,
                  NoteType(rawValue: card.noteTypeRaw) != nil,
                  card.interval.isFinite, card.interval >= 0,
                  card.easeFactor.isFinite, card.fsrsStability.isFinite,
                  card.fsrsDifficulty.isFinite, card.learningStep >= 0,
                  card.repetitions >= 0, card.lapseCount >= 0,
                  card.fsrsReps >= 0, card.fsrsLapses >= 0 else {
                throw BackupArchiveError.invalid("invalid card scheduling state")
            }
            try Self.validateDates([card.createdAt, card.modifiedAt, card.dueDate] + [card.lastReviewDate, card.buriedUntil].compactMap { $0 })
        }
        for log in reviewLogs {
            if let id = log.cardID, !cardIDs.contains(id) {
                throw BackupArchiveError.invalid("a review's card is missing")
            }
            guard log.intervalBefore.isFinite, log.intervalAfter.isFinite,
                  log.easeFactorBefore.isFinite, log.easeFactorAfter.isFinite else {
                throw BackupArchiveError.invalid("invalid review history")
            }
            try Self.validateDates([log.reviewDate])
        }
        try Self.validateDates([createdAt] + tags.map(\.createdAt))
        var paths = Set<String>()
        for asset in media ?? [] {
            let path = try MediaManager.validatedRelativePath(asset.relativePath)
            guard paths.insert(path.lowercased()).inserted else {
                throw BackupArchiveError.invalid("duplicate media path")
            }
        }
    }

    private static func requireUnique(_ ids: [UUID], kind: String) throws {
        guard Set(ids).count == ids.count else { throw BackupArchiveError.invalid("duplicate \(kind) IDs") }
    }

    private static func validateDates(_ dates: [Date]) throws {
        guard dates.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }) else {
            throw BackupArchiveError.invalid("invalid date")
        }
    }

    private static func legacyArchive(from data: Data) throws -> BackupArchive {
        let legacyDecks = try ImportExportManager.decodeLegacyDecks(from: data)
        let schema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let temporaryStore = try ModelContainer(for: schema, configurations: [configuration])
        let temporaryContext = ModelContext(temporaryStore)
        temporaryContext.autosaveEnabled = false
        // Legacy conversion uses an isolated store, never the live database.
        _ = try ImportExportManager.insertLegacyDecks(legacyDecks, context: temporaryContext)
        try temporaryContext.save()
        let archive = BackupArchive(
            formatVersion: 2,
            createdAt: Date(),
            decks: try temporaryContext.fetch(FetchDescriptor<Deck>()).map(BackupDeckRecord.init),
            cards: try temporaryContext.fetch(FetchDescriptor<Card>()).map(BackupCardRecord.init),
            reviewLogs: try temporaryContext.fetch(FetchDescriptor<ReviewLog>()).map(BackupReviewRecord.init),
            tags: try temporaryContext.fetch(FetchDescriptor<Tag>()).map(BackupTagRecord.init),
            media: nil
        )
        try archive.validate()
        return archive
    }
}
