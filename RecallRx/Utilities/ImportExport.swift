import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Deck Extension for Convenience

extension Deck {
    var deckDescription: String {
        get { descriptionText }
        set { descriptionText = newValue }
    }
    
    convenience init(name: String, deckDescription: String) {
        self.init(name: name, descriptionText: deckDescription)
    }
}

// MARK: - Export Data Models

struct DeckExportData: Codable {
    let deckName: String
    let deckDescription: String
    let cards: [CardExportData]
    let exportDate: Date
    let version: Int
    
    init(deckName: String, deckDescription: String = "", cards: [CardExportData], exportDate: Date = Date(), version: Int = 1) {
        self.deckName = deckName
        self.deckDescription = deckDescription
        self.cards = cards
        self.exportDate = exportDate
        self.version = version
    }
    
    enum CodingKeys: String, CodingKey {
        case deckName
        case deckDescription
        case cards
        case exportDate
        case version
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deckName = try container.decode(String.self, forKey: .deckName)
        self.deckDescription = try container.decodeIfPresent(String.self, forKey: .deckDescription) ?? ""
        self.cards = try container.decode([CardExportData].self, forKey: .cards)
        self.exportDate = try container.decodeIfPresent(Date.self, forKey: .exportDate) ?? Date()
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

struct ReviewLogExportData: Codable {
    let rating: Int
    let reviewDate: Date
    let timeTakenMs: Int
    let intervalBefore: Double
    let intervalAfter: Double
    let easeFactorBefore: Double
    let easeFactorAfter: Double
    let cardStateBefore: String
    let cardStateAfter: String
}

struct CardExportData: Codable {
    let front: String
    let back: String
    let tags: [String]
    let noteType: String
    let interval: Double
    let easeFactor: Double
    let repetitions: Int
    let dueDate: Date
    let state: String
    let extra: String
    let firstAid: String
    let sketchy: String
    let pathoma: String
    let clinicalPearls: String
    let lapseCount: Int
    let fsrsStability: Double
    let fsrsDifficulty: Double
    let fsrsReps: Int
    let fsrsLapses: Int
    let reviewLogs: [ReviewLogExportData]
    
    init(
        front: String,
        back: String,
        tags: [String] = [],
        noteType: String = "basic",
        interval: Double = 0.0,
        easeFactor: Double = AppConstants.defaultEaseFactor,
        repetitions: Int = 0,
        dueDate: Date = Date(),
        state: String = "new",
        extra: String = "",
        firstAid: String = "",
        sketchy: String = "",
        pathoma: String = "",
        clinicalPearls: String = "",
        lapseCount: Int = 0,
        fsrsStability: Double = 0.0,
        fsrsDifficulty: Double = 0.0,
        fsrsReps: Int = 0,
        fsrsLapses: Int = 0,
        reviewLogs: [ReviewLogExportData] = []
    ) {
        self.front = front
        self.back = back
        self.tags = tags
        self.noteType = noteType
        self.interval = interval
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.state = state
        self.extra = extra
        self.firstAid = firstAid
        self.sketchy = sketchy
        self.pathoma = pathoma
        self.clinicalPearls = clinicalPearls
        self.lapseCount = lapseCount
        self.fsrsStability = fsrsStability
        self.fsrsDifficulty = fsrsDifficulty
        self.fsrsReps = fsrsReps
        self.fsrsLapses = fsrsLapses
        self.reviewLogs = reviewLogs
    }
    
    enum CodingKeys: String, CodingKey {
        case front, back, tags, noteType, interval, easeFactor, repetitions, dueDate, state, extra, firstAid, sketchy, pathoma, clinicalPearls
        case lapseCount, fsrsStability, fsrsDifficulty, fsrsReps, fsrsLapses, reviewLogs
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.front = try container.decode(String.self, forKey: .front)
        self.back = try container.decodeIfPresent(String.self, forKey: .back) ?? ""
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.noteType = try container.decodeIfPresent(String.self, forKey: .noteType) ?? "basic"
        self.interval = try container.decodeIfPresent(Double.self, forKey: .interval) ?? 0.0
        self.easeFactor = try container.decodeIfPresent(Double.self, forKey: .easeFactor) ?? AppConstants.defaultEaseFactor
        self.repetitions = try container.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0
        self.dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate) ?? Date()
        self.state = try container.decodeIfPresent(String.self, forKey: .state) ?? "new"
        self.extra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        self.firstAid = try container.decodeIfPresent(String.self, forKey: .firstAid) ?? ""
        self.sketchy = try container.decodeIfPresent(String.self, forKey: .sketchy) ?? ""
        self.pathoma = try container.decodeIfPresent(String.self, forKey: .pathoma) ?? ""
        self.clinicalPearls = try container.decodeIfPresent(String.self, forKey: .clinicalPearls) ?? ""
        self.lapseCount = try container.decodeIfPresent(Int.self, forKey: .lapseCount) ?? 0
        self.fsrsStability = try container.decodeIfPresent(Double.self, forKey: .fsrsStability) ?? 0.0
        self.fsrsDifficulty = try container.decodeIfPresent(Double.self, forKey: .fsrsDifficulty) ?? 0.0
        self.fsrsReps = try container.decodeIfPresent(Int.self, forKey: .fsrsReps) ?? 0
        self.fsrsLapses = try container.decodeIfPresent(Int.self, forKey: .fsrsLapses) ?? 0
        self.reviewLogs = try container.decodeIfPresent([ReviewLogExportData].self, forKey: .reviewLogs) ?? []
    }
}

// MARK: - Import/Export Errors

enum ImportError: LocalizedError {
    case invalidData
    case invalidCSVFormat
    case emptyFile
    case decodingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "The file data is invalid or could not be read."
        case .invalidCSVFormat:
            return "The CSV format is invalid. Expected at least Front and Back columns."
        case .emptyFile:
            return "The file to import is empty."
        case .decodingFailed(let reason):
            return "Failed to decode deck data: \(reason)"
        }
    }
}

// MARK: - UTType Extensions

extension UTType {
    static var ankiDeckJSON: UTType { UTType.json }
    static var ankiDeckCSV: UTType { UTType.commaSeparatedText }
    static var ankiPackage: UTType {
        UTType(importedAs: "com.ankiclone.deck", conformingTo: .json)
    }
}

// MARK: - ImportExportManager

class ImportExportManager {
    
    /// Export deck to JSON
    static func exportDeck(_ deck: Deck) throws -> Data {
        let cardExports: [CardExportData] = deck.cards.map { card in
            let logs = card.reviewLogs.map { log in
                ReviewLogExportData(
                    rating: log.rating,
                    reviewDate: log.reviewDate,
                    timeTakenMs: log.timeTakenMs,
                    intervalBefore: log.intervalBefore,
                    intervalAfter: log.intervalAfter,
                    easeFactorBefore: log.easeFactorBefore,
                    easeFactorAfter: log.easeFactorAfter,
                    cardStateBefore: log.cardStateBefore,
                    cardStateAfter: log.cardStateAfter
                )
            }
            return CardExportData(
                front: card.front,
                back: card.back,
                tags: card.tags,
                noteType: card.noteTypeRaw,
                interval: card.interval,
                easeFactor: card.easeFactor,
                repetitions: card.repetitions,
                dueDate: card.dueDate,
                state: card.stateRaw,
                extra: card.extra,
                firstAid: card.firstAid,
                sketchy: card.sketchy,
                pathoma: card.pathoma,
                clinicalPearls: card.clinicalPearls,
                lapseCount: card.lapseCount,
                fsrsStability: card.fsrsStability,
                fsrsDifficulty: card.fsrsDifficulty,
                fsrsReps: card.fsrsReps,
                fsrsLapses: card.fsrsLapses,
                reviewLogs: logs
            )
        }
        
        let exportData = DeckExportData(
            deckName: deck.name,
            deckDescription: deck.deckDescription,
            cards: cardExports,
            exportDate: Date(),
            version: 1
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportData)
    }
    
    /// Export a complete versioned library archive, including media and scheduling state.
    static func exportAllDecks(context: ModelContext, mediaDirectoryURL: URL? = nil) throws -> Data {
        try BackupArchive.capture(
            context: context,
            mediaDirectoryURL: mediaDirectoryURL ?? MediaManager.shared.directoryURL
        ).encoded()
    }

    /// Import complete archives and legacy single-deck / multi-deck JSON without partial saves.
    static func importAllDecks(
        from data: Data,
        context: ModelContext,
        mediaDirectoryURL: URL? = nil
    ) throws -> [Deck] {
        let archive = try BackupArchive.decode(data)
        let media = try archive.media.map {
            try BackupMediaStaging(
                records: $0,
                liveDirectory: mediaDirectoryURL ?? MediaManager.shared.directoryURL,
                preserveExisting: true
            )
        }
        try context.save()
        let autosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosaveEnabled }
        do {
            let decks = try BackupStoreWriter.insert(archive, context: context)
            try media?.install()
            try context.save()
            media?.finish()
            return decks
        } catch {
            context.rollback()
            do {
                try media?.rollback()
            } catch let recoveryError {
                throw BackupArchiveError.mediaRollbackFailed(
                    original: error, recovery: recoveryError,
                    recoveryDirectory: media?.recoveryDirectory
                )
            }
            throw error
        }
    }

    /// Pure legacy decoding is shared with backup validation before any live mutation.
    static func decodeLegacyDecks(from data: Data) throws -> [DeckExportData] {
        guard !data.isEmpty else {
            throw ImportError.emptyFile
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let dateString = try? container.decode(String.self) {
                let isoFormatter = ISO8601DateFormatter()
                if let date = isoFormatter.date(from: dateString) {
                    return date
                }
                let standardFormatter = DateFormatter()
                standardFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                if let date = standardFormatter.date(from: dateString) {
                    return date
                }
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid date format")
            )
        }
        
        var deckDataList: [DeckExportData] = []
        if let multiDecks = try? decoder.decode([DeckExportData].self, from: data) {
            deckDataList = multiDecks
        } else if let singleDeck = try? decoder.decode(DeckExportData.self, from: data) {
            deckDataList = [singleDeck]
        } else {
            throw ImportError.decodingFailed("Could not decode snapshot decks format.")
        }
        
        return deckDataList
    }

    /// Build legacy records in the caller's unsaved context. The caller owns the transaction.
    @discardableResult
    static func insertLegacyDecks(_ deckDataList: [DeckExportData], context: ModelContext) throws -> [Deck] {
        var importedDecks: [Deck] = []
        var existingTagNames: Set<String> = []
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        for tag in existingTags {
            existingTagNames.insert(tag.name.lowercased())
        }
        
        for deckData in deckDataList {
            let deck = Deck(name: deckData.deckName, deckDescription: deckData.deckDescription)
            context.insert(deck)
            
            for cardExport in deckData.cards {
                var validTags: [String] = []
                for tagName in cardExport.tags {
                    let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    validTags.append(trimmed)
                    let key = trimmed.lowercased()
                    if !existingTagNames.contains(key) {
                        let newTag = Tag(name: trimmed)
                        context.insert(newTag)
                        existingTagNames.insert(key)
                    }
                }
                
                let card = Card(
                    front: cardExport.front,
                    back: cardExport.back,
                    deck: deck,
                    tags: validTags,
                    noteTypeRaw: cardExport.noteType,
                    createdAt: cardExport.reviewLogs.map(\.reviewDate).min() ?? deckData.exportDate,
                    modifiedAt: cardExport.reviewLogs.map(\.reviewDate).max() ?? deckData.exportDate,
                    lapseCount: cardExport.lapseCount,
                    interval: cardExport.interval,
                    easeFactor: cardExport.easeFactor,
                    repetitions: cardExport.repetitions,
                    dueDate: cardExport.dueDate,
                    lastReviewDate: cardExport.reviewLogs.map(\.reviewDate).max(),
                    stateRaw: cardExport.state,
                    extra: cardExport.extra,
                    firstAid: cardExport.firstAid,
                    sketchy: cardExport.sketchy,
                    pathoma: cardExport.pathoma,
                    clinicalPearls: cardExport.clinicalPearls,
                    fsrsStability: cardExport.fsrsStability,
                    fsrsDifficulty: cardExport.fsrsDifficulty,
                    fsrsReps: cardExport.fsrsReps,
                    fsrsLapses: cardExport.fsrsLapses
                )
                
                context.insert(card)
                deck.cards.append(card)
                
                // Re-hydrate ReviewLogs
                for logExport in cardExport.reviewLogs {
                    let log = ReviewLog(
                        card: card,
                        rating: logExport.rating,
                        reviewDate: logExport.reviewDate,
                        timeTakenMs: logExport.timeTakenMs,
                        intervalBefore: logExport.intervalBefore,
                        intervalAfter: logExport.intervalAfter,
                        easeFactorBefore: logExport.easeFactorBefore,
                        easeFactorAfter: logExport.easeFactorAfter,
                        cardStateBefore: logExport.cardStateBefore,
                        cardStateAfter: logExport.cardStateAfter
                    )
                    context.insert(log)
                    card.reviewLogs.append(log)
                }
            }
            importedDecks.append(deck)
        }
        
        return importedDecks
    }
    
    /// Import deck from JSON data
    static func importDeck(from data: Data, context: ModelContext) throws -> Deck {
        let decks = try importAllDecks(from: data, context: context)
        guard let first = decks.first else {
            throw ImportError.emptyFile
        }
        return first
    }
    
    /// Export as CSV (front, back, tags)
    static func exportAsCSV(_ deck: Deck) throws -> String {
        var lines: [String] = []
        lines.append("Front,Back,Tags")
        
        for card in deck.cards {
            let frontEscaped = escapeCSVField(card.front)
            let backEscaped = escapeCSVField(card.back)
            let tagsEscaped = escapeCSVField(card.tags.joined(separator: " "))
            lines.append("\(frontEscaped),\(backEscaped),\(tagsEscaped)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Import from CSV
    static func importFromCSV(_ csv: String, deckName: String, context: ModelContext) throws -> Deck {
        guard !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }
        
        let rows = parseCSV(csv)
        guard !rows.isEmpty else {
            throw ImportError.invalidCSVFormat
        }
        
        var dataRows = rows
        if let firstRow = dataRows.first, firstRow.count >= 2 {
            let col0 = firstRow[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let col1 = firstRow[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if (col0 == "front" || col0 == "question") && (col1 == "back" || col1 == "answer") {
                dataRows.removeFirst()
            }
        }
        
        guard !dataRows.isEmpty else {
            throw ImportError.invalidCSVFormat
        }
        
        try context.save()
        let autosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosaveEnabled }

        let deck = Deck(name: deckName, deckDescription: "")
        context.insert(deck)
        
        var existingTagNames: Set<String> = []
        let existingTags: [Tag]
        do {
            existingTags = try context.fetch(FetchDescriptor<Tag>())
        } catch {
            context.rollback()
            throw error
        }
        for tag in existingTags {
            existingTagNames.insert(tag.name.lowercased())
        }

        for row in dataRows {
            guard row.count >= 2 else { continue }
            let front = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty || !back.isEmpty else { continue }
            
            var validTags: [String] = []
            if row.count > 2 {
                let tagRaw = row[2].trimmingCharacters(in: .whitespacesAndNewlines)
                let tagParts: [String]
                if tagRaw.contains(";") {
                    tagParts = tagRaw.components(separatedBy: ";")
                } else if tagRaw.contains(",") {
                    tagParts = tagRaw.components(separatedBy: ",")
                } else {
                    tagParts = tagRaw.components(separatedBy: .whitespaces)
                }
                
                for tagName in tagParts {
                    let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    validTags.append(trimmed)
                    let key = trimmed.lowercased()
                    if !existingTagNames.contains(key) {
                        let newTag = Tag(name: trimmed)
                        context.insert(newTag)
                        existingTagNames.insert(key)
                    }
                }
            }
            
            let card = Card(
                front: front,
                back: back,
                deck: deck,
                tags: validTags,
                noteTypeRaw: NoteType.basic.rawValue,
                interval: 0.0,
                easeFactor: AppConstants.defaultEaseFactor,
                repetitions: 0,
                dueDate: Date(),
                stateRaw: CardState.new.rawValue
            )
            
            context.insert(card)
            deck.cards.append(card)
        }
        
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return deck
    }
    
    /// Generate plain text summary for sharing
    static func generateShareText(for deck: Deck) -> String {
        let cardCount = deck.cards.count
        var text = "📚 \(deck.name)\n"
        if !deck.deckDescription.isEmpty {
            text += "\(deck.deckDescription)\n\n"
        } else {
            text += "\n"
        }
        text += "Total Cards: \(cardCount)\n"
        
        let matureCount = deck.cards.filter { $0.interval >= Double(AppConstants.matureInterval) }.count
        let learningCount = deck.cards.filter { $0.state == .learning || $0.state == .relearning }.count
        let newCount = deck.cards.filter { $0.state == .new }.count
        let reviewCount = deck.cards.filter { $0.state == .review }.count
        
        text += "• New: \(newCount)\n"
        text += "• Learning: \(learningCount)\n"
        text += "• Review: \(reviewCount)\n"
        text += "• Mature: \(matureCount)\n\n"
        text += "Shared via RecallRx"
        return text
    }
    
    // MARK: - Private CSV Helpers
    
    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
    
    private static func parseCSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        var iterator = csv.makeIterator()
        var peekChar: Character? = iterator.next()
        
        while let char = peekChar {
            peekChar = iterator.next()
            
            if insideQuotes {
                if char == "\"" {
                    if peekChar == "\"" {
                        currentField.append("\"")
                        peekChar = iterator.next()
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    insideQuotes = true
                } else if char == "," {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char == "\r" {
                    if peekChar == "\n" {
                        peekChar = iterator.next()
                    }
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else if char == "\n" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                } else {
                    currentField.append(char)
                }
            }
        }
        
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(currentRow)
            }
        }
        
        return rows
    }
}
