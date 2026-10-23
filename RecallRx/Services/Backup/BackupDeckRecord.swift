import Foundation

/// Lossless persistence record for versioned backups.
struct BackupDeckRecord: Codable, Equatable {
    let id: UUID
    let name: String
    let descriptionText: String
    let createdAt: Date
    let modifiedAt: Date
    let isCollapsed: Bool
    let parentDeckID: UUID?
    let newCardsPerDay: Int
    let reviewsPerDay: Int

    init(_ model: Deck) {
        id = model.id
        name = model.name
        descriptionText = model.descriptionText
        createdAt = model.createdAt
        modifiedAt = model.modifiedAt
        isCollapsed = model.isCollapsed
        parentDeckID = model.parentDeckID
        newCardsPerDay = model.newCardsPerDay
        reviewsPerDay = model.reviewsPerDay
    }
}
