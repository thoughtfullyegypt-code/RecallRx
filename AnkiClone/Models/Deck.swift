import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isCollapsed: Bool = false
    var parentDeckID: UUID?
    var newCardsPerDay: Int = 20
    var reviewsPerDay: Int = 200
    
    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card] = []
    
    var displayName: String {
        if parentDeckID != nil || name.contains("::") {
            let components = name.components(separatedBy: "::")
            if let leaf = components.last, !leaf.trimmingCharacters(in: .whitespaces).isEmpty {
                return leaf.trimmingCharacters(in: .whitespaces)
            }
        }
        return name
    }
    
    var newCards: Int {
        cards.filter { !$0.isSuspended && !$0.isBuried && $0.state == .new }.count
    }
    
    var learningCards: Int {
        cards.filter { !$0.isSuspended && !$0.isBuried && ($0.state == .learning || $0.state == .relearning) && $0.dueDate <= Date.now }.count
    }
    
    var dueCards: Int {
        cards.filter { !$0.isSuspended && !$0.isBuried && $0.state == .review && $0.dueDate <= Date.now }.count
    }
    
    var totalCards: Int {
        cards.count
    }
    
    var totalDueCount: Int {
        learningCards + dueCards + min(newCards, newCardsPerDay)
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isCollapsed: Bool = false,
        parentDeckID: UUID? = nil,
        newCardsPerDay: Int = 20,
        reviewsPerDay: Int = 200,
        cards: [Card] = []
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isCollapsed = isCollapsed
        self.parentDeckID = parentDeckID
        self.newCardsPerDay = newCardsPerDay
        self.reviewsPerDay = reviewsPerDay
        self.cards = cards
    }
}
