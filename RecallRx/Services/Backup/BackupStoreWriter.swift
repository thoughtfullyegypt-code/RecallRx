import Foundation
import SwiftData

enum BackupStoreWriter {
    static func removeAllModels(context: ModelContext) throws {
        // Fetch every collection first so a fetch failure cannot leave a half-mutated context.
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        let decks = try context.fetch(FetchDescriptor<Deck>())
        let tags = try context.fetch(FetchDescriptor<Tag>())
        for log in logs { context.delete(log) }
        for card in cards { context.delete(card) }
        for deck in decks { context.delete(deck) }
        for tag in tags { context.delete(tag) }
    }

    @discardableResult
    static func insert(_ archive: BackupArchive, context: ModelContext, checkingExistingIDs: Bool = true) throws -> [Deck] {
        if checkingExistingIDs {
            // Additive imports must not create duplicate identities in an existing library.
            let existingDeckIDs = Set(try context.fetch(FetchDescriptor<Deck>()).map(\.id))
            let existingCardIDs = Set(try context.fetch(FetchDescriptor<Card>()).map(\.id))
            let existingLogIDs = Set(try context.fetch(FetchDescriptor<ReviewLog>()).map(\.id))
            let existingTagIDs = Set(try context.fetch(FetchDescriptor<Tag>()).map(\.id))
            guard existingDeckIDs.isDisjoint(with: archive.decks.map(\.id)),
                  existingCardIDs.isDisjoint(with: archive.cards.map(\.id)),
                  existingLogIDs.isDisjoint(with: archive.reviewLogs.map(\.id)),
                  existingTagIDs.isDisjoint(with: archive.tags.map(\.id)) else {
                throw BackupArchiveError.invalid("the library already contains these records; use Restore Snapshot to replace it")
            }

        }

        var decksByID: [UUID: Deck] = [:]
        var importedDecks: [Deck] = []
        for record in archive.decks {
            let deck = Deck(
                id: record.id, name: record.name, descriptionText: record.descriptionText,
                createdAt: record.createdAt, modifiedAt: record.modifiedAt,
                isCollapsed: record.isCollapsed, parentDeckID: record.parentDeckID,
                newCardsPerDay: record.newCardsPerDay, reviewsPerDay: record.reviewsPerDay
            )
            context.insert(deck)
            decksByID[deck.id] = deck
            importedDecks.append(deck)
        }
        var cardsByID: [UUID: Card] = [:]
        for record in archive.cards {
            let deck = record.deckID.flatMap { decksByID[$0] }
            let card = Card(
                id: record.id, front: record.front, back: record.back,
                deck: deck, tags: record.tags, noteTypeRaw: record.noteTypeRaw,
                createdAt: record.createdAt, modifiedAt: record.modifiedAt,
                isSuspended: record.isSuspended, isBuried: record.isBuried,
                buriedUntil: record.buriedUntil, lapseCount: record.lapseCount,
                interval: record.interval, easeFactor: record.easeFactor,
                repetitions: record.repetitions, dueDate: record.dueDate,
                lastReviewDate: record.lastReviewDate, stateRaw: record.stateRaw,
                learningStep: record.learningStep, queueRaw: record.queueRaw,
                extra: record.extra, firstAid: record.firstAid, sketchy: record.sketchy,
                pathoma: record.pathoma, clinicalPearls: record.clinicalPearls,
                fsrsStability: record.fsrsStability, fsrsDifficulty: record.fsrsDifficulty,
                fsrsReps: record.fsrsReps, fsrsLapses: record.fsrsLapses
            )
            context.insert(card)
            if let deck, !deck.cards.contains(where: { $0.id == card.id }) { deck.cards.append(card) }
            cardsByID[card.id] = card
        }
        for record in archive.reviewLogs {
            let card = record.cardID.flatMap { cardsByID[$0] }
            let log = ReviewLog(
                id: record.id, card: card, rating: record.rating, reviewDate: record.reviewDate,
                timeTakenMs: record.timeTakenMs, intervalBefore: record.intervalBefore,
                intervalAfter: record.intervalAfter, easeFactorBefore: record.easeFactorBefore,
                easeFactorAfter: record.easeFactorAfter, cardStateBefore: record.cardStateBefore,
                cardStateAfter: record.cardStateAfter
            )
            context.insert(log)
            if let card, !card.reviewLogs.contains(where: { $0.id == log.id }) { card.reviewLogs.append(log) }
        }
        for record in archive.tags {
            context.insert(Tag(id: record.id, name: record.name, createdAt: record.createdAt))
        }
        return importedDecks
    }
}
