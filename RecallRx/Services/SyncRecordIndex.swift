import Foundation
import SwiftData

/// Fetch each entity collection once per pulled batch, rather than once per record.
struct SyncRecordIndex {
    var decks: [UUID: Deck]
    var cards: [UUID: Card]
    var logs: [UUID: ReviewLog]
    var cardIDsByDeck: [UUID: Set<UUID>] = [:]
    var logIDsByCard: [UUID: Set<UUID>] = [:]

    init(context: ModelContext) throws {
        decks = Dictionary(try context.fetch(FetchDescriptor<Deck>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cards = Dictionary(try context.fetch(FetchDescriptor<Card>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        logs = Dictionary(try context.fetch(FetchDescriptor<ReviewLog>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for card in cards.values {
            if let deckID = card.deck?.id { cardIDsByDeck[deckID, default: []].insert(card.id) }
        }
        for log in logs.values {
            if let cardID = log.card?.id { logIDsByCard[cardID, default: []].insert(log.id) }
        }
    }
}
