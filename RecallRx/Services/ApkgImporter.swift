import Foundation
import SwiftData

/// Imports a complete Anki package without merging cards merely because their prompts look alike.
final class ApkgImporter {
    struct ApkgImportResult: Sendable {
        let decksCount: Int
        /// Newly inserted cards; updates are reported separately and do not inflate this count.
        let cardsCount: Int
        let updatedCardsCount: Int
        let mediaFilesCount: Int
        let deckNames: [String]
        let message: String
    }

    enum ApkgError: LocalizedError {
        case fileNotFound
        case invalidZipArchive
        case invalidMetadata
        case missingCollectionDatabase
        case sqliteError(String)
        case unsupportedCollection(String)
        case emptyCollection

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "The Anki package could not be read."
            case .invalidZipArchive: return "The Anki ZIP archive is corrupt, encrypted, or contains invalid entries."
            case .invalidMetadata: return "The Anki package contains invalid note type or media metadata."
            case .missingCollectionDatabase: return "The package is missing its Anki collection database."
            case .sqliteError(let message): return "Anki database error: \(message)"
            case .unsupportedCollection(let message): return message
            case .emptyCollection: return "The Anki package contains no importable cards."
            }
        }
    }

    @MainActor
    static func importApkg(
        from fileURL: URL,
        into context: ModelContext,
        mediaDirectoryURL: URL? = nil
    ) throws -> ApkgImportResult {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("apkg_extract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try AnkiArchiveReader.extract(fileURL, to: temporary)
        let (database, modern) = try collectionDatabase(in: temporary)
        let package = try AnkiImportPackage(databaseURL: database)
        let media = try AnkiMediaImportTransaction(
            extractedDirectory: temporary,
            destination: mediaDirectoryURL ?? MediaManager.shared.directoryURL,
            modern: modern
        )
        // Render everything before changing the library, so unsupported templates cannot leave half an import.
        let rendered = try package.cards.map { card -> AnkiTemplateRenderer.RenderedCard in
            guard let note = package.notes[card.noteID], let model = package.models[note.modelID], let deckName = package.deckNames[card.deckID] else {
                throw ApkgError.invalidMetadata
            }
            return try AnkiTemplateRenderer.render(
                card: card, note: note, model: model, deckName: deckName,
                collectionCreation: package.creationDate, mediaNames: media.names
            )
        }

        // A separate context isolates rollback from any unrelated draft changes in the caller's context.
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        do {
            let decks = try transaction.fetch(FetchDescriptor<Deck>())
            let existing = try transaction.fetch(FetchDescriptor<Card>())
            var cardsByID: [UUID: Card] = [:]
            for card in existing { cardsByID[card.id] = card }
            var targetDecks: [Int64: Deck] = [:]
            var newDeckCount = 0
            let referencedDecks = Set(package.cards.map(\.deckID))
            for deckID in referencedDecks.sorted() {
                guard let name = package.deckNames[deckID] else { throw ApkgError.invalidMetadata }
                let stableID = AnkiTemplateRenderer.stableID("RecallRx.Anki.deck:\(Int64(package.creationDate.timeIntervalSince1970)):\(deckID)")
                if let deck = decks.first(where: { $0.id == stableID }) ?? decks.first(where: { $0.name == name }) {
                    targetDecks[deckID] = deck
                } else {
                    let deck = Deck(id: stableID, name: name, descriptionText: "Imported from Anki")
                    transaction.insert(deck)
                    targetDecks[deckID] = deck
                    newDeckCount += 1
                }
            }
            for deck in targetDecks.values {
                let parentName = deck.name.components(separatedBy: "::").dropLast().joined(separator: "::")
                if let parent = targetDecks.values.first(where: { $0.name == parentName }) ?? decks.first(where: { $0.name == parentName }) {
                    deck.parentDeckID = parent.id
                }
            }
            let now = Date()
            var insertedCount = 0
            var updatedCount = 0
            for (source, content) in zip(package.cards, rendered) {
                guard let note = package.notes[source.noteID], let deck = targetDecks[source.deckID] else { throw ApkgError.invalidMetadata }
                let card: Card
                let isNew: Bool
                if let match = cardsByID[content.id] {
                    card = match
                    isNew = false
                    updatedCount += 1
                } else {
                    card = Card(id: content.id)
                    transaction.insert(card)
                    cardsByID[content.id] = card
                    isNew = true
                    insertedCount += 1
                }
                let sourceModified = max(source.modified, note.modified)
                let shouldImportSchedule = isNew || (card.reviewLogs.isEmpty && card.modifiedAt <= source.modified)
                card.front = content.front
                card.back = content.back
                card.noteType = content.noteType
                card.extra = content.extra
                card.firstAid = content.firstAid
                card.sketchy = content.sketchy
                card.pathoma = content.pathoma
                card.clinicalPearls = content.clinicalPearls
                card.tags = Array(Set(card.tags).union(note.tags)).sorted()
                card.deck = deck
                // Once studied in RecallRx, re-importing the package must not undo the user's reviews.
                if shouldImportSchedule {
                    applySchedule(source, package: package, to: card, now: now)
                }
                if isNew { card.createdAt = Date(timeIntervalSince1970: Double(note.id) / 1000) }
                card.modifiedAt = isNew ? sourceModified : now
            }
            try media.install()
            try transaction.save()
            let names = Set(targetDecks.values.map(\.name)).sorted()
            return ApkgImportResult(
                decksCount: newDeckCount, cardsCount: insertedCount, updatedCardsCount: updatedCount,
                mediaFilesCount: media.count, deckNames: names,
                message: "Imported \(insertedCount) new cards and updated \(updatedCount) existing cards across \(names.count) decks, with \(media.count) media files."
            )
        } catch {
            transaction.rollback()
            media.rollback()
            throw error
        }
    }

    private static func applySchedule(_ source: AnkiImportPackage.ImportedCard, package: AnkiImportPackage, to card: Card, now: Date) {
        let schedule = AnkiSchedulingState(card: source, collectionCreation: package.creationDate, now: now)
        card.state = schedule.state
        card.queueRaw = schedule.state.rawValue
        card.interval = schedule.interval
        card.dueDate = schedule.dueDate
        card.lastReviewDate = schedule.lastReviewDate
        card.learningStep = schedule.learningStep
        card.repetitions = source.repetitions
        card.lapseCount = source.lapses
        card.easeFactor = source.factor > 0 ? Double(source.factor) / 1000 : AppConstants.defaultEaseFactor
        card.isSuspended = source.queue == -1
        card.isBuried = source.queue == -2 || source.queue == -3
        card.buriedUntil = card.isBuried ? Calendar.current.date(byAdding: .day, value: 1, to: now.startOfDay) : nil
        card.fsrsStability = source.fsrsStability
        card.fsrsDifficulty = source.fsrsDifficulty
        card.fsrsReps = source.repetitions
        card.fsrsLapses = source.lapses
    }

    private static func collectionDatabase(in directory: URL) throws -> (URL, Bool) {
        // Recent exports may include a compatibility stub collection.anki2. Prefer the real newest database.
        for name in ["collection.anki21b", "collection.anki21", "collection.anki2"] {
            let source = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let data = try decompressZstdIfNeeded(Data(contentsOf: source))
            guard data.starts(with: Data("SQLite format 3".utf8)) else { throw ApkgError.invalidMetadata }
            let decoded = directory.appendingPathComponent("import.sqlite")
            try data.write(to: decoded)
            return (decoded, name == "collection.anki21b")
        }
        throw ApkgError.missingCollectionDatabase
    }

    static func decompressZstdIfNeeded(_ data: Data) throws -> Data {
        guard data.starts(with: [0x28, 0xb5, 0x2f, 0xfd]) else { return data }
        return try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw ApkgError.invalidMetadata }
            var output: UnsafeMutableRawPointer?
            var size = 0
            var message = [CChar](repeating: 0, count: 180)
            let result = recallrx_zstd_decompress(base, data.count, &output, &size, &message, message.count)
            guard result == 0, let output else {
                throw ApkgError.unsupportedCollection(String(cString: message))
            }
            defer { free(output) }
            return Data(bytes: output, count: size)
        }
    }
}
