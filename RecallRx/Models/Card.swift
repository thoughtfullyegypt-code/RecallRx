import Foundation
import SwiftData

enum CardState: String, Codable, CaseIterable, Identifiable, Sendable {
    case new
    case learning
    case review
    case relearning
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .new:
            return "New"
        case .learning:
            return "Learning"
        case .review:
            return "Review"
        case .relearning:
            return "Relearning"
        }
    }
}

@Model
final class Card {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    var deck: Deck?
    var tags: [String] = []
    var noteTypeRaw: String = "basic"
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var isSuspended: Bool = false
    var isBuried: Bool = false
    var buriedUntil: Date? = nil
    var lapseCount: Int = 0
    var interval: Double = 0.0
    var easeFactor: Double = 2.5
    var repetitions: Int = 0
    var dueDate: Date = Date()
    var lastReviewDate: Date?
    var stateRaw: String = "new"
    var learningStep: Int = 0
    var queueRaw: String = "new"
    
    // Optional study notes. The names are internal; the screen calls them Outline, Visual, and Pathology.
    var extra: String = ""
    var firstAid: String = ""
    var sketchy: String = ""
    var pathoma: String = ""
    var clinicalPearls: String = ""
    
    // FSRS (Free Spaced Repetition Scheduler) Fields
    var fsrsStability: Double = 0.0
    var fsrsDifficulty: Double = 0.0
    var fsrsReps: Int = 0
    var fsrsLapses: Int = 0
    
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    var reviewLogs: [ReviewLog] = []
    
    var noteType: NoteType {
        get { NoteType(rawValue: noteTypeRaw) ?? .basic }
        set { 
            noteTypeRaw = newValue.rawValue
            modifiedAt = .now
        }
    }
    
    var state: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { 
            stateRaw = newValue.rawValue
            modifiedAt = .now
        }
    }
    
    init(
        id: UUID = UUID(),
        front: String = "",
        back: String = "",
        deck: Deck? = nil,
        tags: [String] = [],
        noteTypeRaw: String = NoteType.basic.rawValue,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isSuspended: Bool = false,
        isBuried: Bool = false,
        buriedUntil: Date? = nil,
        lapseCount: Int = 0,
        interval: Double = 0.0,
        easeFactor: Double = 2.5,
        repetitions: Int = 0,
        dueDate: Date = Date(),
        lastReviewDate: Date? = nil,
        stateRaw: String = CardState.new.rawValue,
        learningStep: Int = 0,
        queueRaw: String = "new",
        extra: String = "",
        firstAid: String = "",
        sketchy: String = "",
        pathoma: String = "",
        clinicalPearls: String = "",
        fsrsStability: Double = 0.0,
        fsrsDifficulty: Double = 0.0,
        fsrsReps: Int = 0,
        fsrsLapses: Int = 0,
        reviewLogs: [ReviewLog] = []
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.deck = deck
        self.tags = tags
        self.noteTypeRaw = noteTypeRaw
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isSuspended = isSuspended
        self.isBuried = isBuried
        self.buriedUntil = buriedUntil
        self.lapseCount = lapseCount
        self.interval = interval
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewDate = lastReviewDate
        self.stateRaw = stateRaw
        self.learningStep = learningStep
        self.queueRaw = queueRaw
        self.extra = extra
        self.firstAid = firstAid
        self.sketchy = sketchy
        self.pathoma = pathoma
        self.clinicalPearls = clinicalPearls
        self.fsrsStability = fsrsStability
        self.fsrsDifficulty = fsrsDifficulty
        self.fsrsReps = fsrsReps
        self.fsrsLapses = fsrsLapses
        self.reviewLogs = reviewLogs
    }
    
    convenience init(
        id: UUID = UUID(),
        front: String = "",
        back: String = "",
        deck: Deck? = nil,
        tags: [String] = [],
        noteType: NoteType,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isSuspended: Bool = false,
        isBuried: Bool = false,
        buriedUntil: Date? = nil,
        lapseCount: Int = 0,
        interval: Double = 0.0,
        easeFactor: Double = 2.5,
        repetitions: Int = 0,
        dueDate: Date = Date(),
        lastReviewDate: Date? = nil,
        state: CardState = .new,
        learningStep: Int = 0,
        queueRaw: String = "new",
        extra: String = "",
        firstAid: String = "",
        sketchy: String = "",
        pathoma: String = "",
        clinicalPearls: String = "",
        reviewLogs: [ReviewLog] = []
    ) {
        self.init(
            id: id,
            front: front,
            back: back,
            deck: deck,
            tags: tags,
            noteTypeRaw: noteType.rawValue,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isSuspended: isSuspended,
            isBuried: isBuried,
            buriedUntil: buriedUntil,
            lapseCount: lapseCount,
            interval: interval,
            easeFactor: easeFactor,
            repetitions: repetitions,
            dueDate: dueDate,
            lastReviewDate: lastReviewDate,
            stateRaw: state.rawValue,
            learningStep: learningStep,
            queueRaw: queueRaw,
            extra: extra,
            firstAid: firstAid,
            sketchy: sketchy,
            pathoma: pathoma,
            clinicalPearls: clinicalPearls,
            reviewLogs: reviewLogs
        )
    }
    
    var hasMedicalResources: Bool {
        !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !firstAid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !sketchy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !pathoma.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !clinicalPearls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - FSRS Helpers
    func retrievability(at date: Date = Date()) -> Double {
        guard fsrsStability > 0 else { return 1.0 }
        let elapsedDays = max(0.0, date.timeIntervalSince(lastReviewDate ?? createdAt) / 86400.0)
        return FSRSAlgorithm.retrievability(stability: fsrsStability, elapsedDays: elapsedDays, parameters: Scheduler.fsrsParameters)
    }
    
    var fsrsDifficultyDescription: String {
        guard fsrsDifficulty > 0 else { return "N/A" }
        return String(format: "%.1f / 10", fsrsDifficulty)
    }
}
