import Foundation
import SwiftData

/// Fetch each entity collection once per pulled batch, rather than once per record.
struct SyncRecordIndex {
    var decks: [UUID: Deck]
    var cards: [UUID: Card]
    var logs: [UUID: ReviewLog]

    init(context: ModelContext) throws {
        decks = Dictionary(try context.fetch(FetchDescriptor<Deck>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cards = Dictionary(try context.fetch(FetchDescriptor<Card>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        logs = Dictionary(try context.fetch(FetchDescriptor<ReviewLog>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
