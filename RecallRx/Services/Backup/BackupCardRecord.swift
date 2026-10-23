import Foundation

/// Lossless persistence record for versioned backups.
struct BackupCardRecord: Codable, Equatable {
    let id: UUID
    let deckID: UUID?
    let front: String
    let back: String
    let tags: [String]
    let noteTypeRaw: String
    let createdAt: Date
    let modifiedAt: Date
    let isSuspended: Bool
    let isBuried: Bool
    let buriedUntil: Date?
    let lapseCount: Int
    let interval: Double
    let easeFactor: Double
    let repetitions: Int
    let dueDate: Date
    let lastReviewDate: Date?
    let stateRaw: String
    let learningStep: Int
    let queueRaw: String
    let extra: String
    let firstAid: String
    let sketchy: String
    let pathoma: String
    let clinicalPearls: String
    let fsrsStability: Double
    let fsrsDifficulty: Double
    let fsrsReps: Int
    let fsrsLapses: Int

    init(_ model: Card) {
        id = model.id
        deckID = model.deck?.id
        front = model.front
        back = model.back
        tags = model.tags
        noteTypeRaw = model.noteTypeRaw
        createdAt = model.createdAt
        modifiedAt = model.modifiedAt
        isSuspended = model.isSuspended
        isBuried = model.isBuried
        buriedUntil = model.buriedUntil
        lapseCount = model.lapseCount
        interval = model.interval
        easeFactor = model.easeFactor
        repetitions = model.repetitions
        dueDate = model.dueDate
        lastReviewDate = model.lastReviewDate
        stateRaw = model.stateRaw
        learningStep = model.learningStep
        queueRaw = model.queueRaw
        extra = model.extra
        firstAid = model.firstAid
        sketchy = model.sketchy
        pathoma = model.pathoma
        clinicalPearls = model.clinicalPearls
        fsrsStability = model.fsrsStability
        fsrsDifficulty = model.fsrsDifficulty
        fsrsReps = model.fsrsReps
        fsrsLapses = model.fsrsLapses
    }
}
