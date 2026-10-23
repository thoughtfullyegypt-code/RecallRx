import Foundation

/// Lossless persistence record for versioned backups.
struct BackupTagRecord: Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date

    init(_ model: Tag) {
        id = model.id
        name = model.name
        createdAt = model.createdAt
    }
}
