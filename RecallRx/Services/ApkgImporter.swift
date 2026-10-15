import Foundation
import SwiftData
import SQLite3
import zlib

/// Anki .apkg Binary Package Importer
/// Unpacks .apkg archives (ZIP container), reads collection.anki2 SQLite database,
/// extracts media assets, and imports decks, notes, clozes, and tags into SwiftData.
final class ApkgImporter {
    
    struct ApkgImportResult: Sendable {
        let decksCount: Int
        let cardsCount: Int
        let mediaFilesCount: Int
        let deckNames: [String]
        let message: String
    }
    
    enum ApkgError: LocalizedError {
        case fileNotFound
        case invalidZipArchive
        case missingCollectionDatabase
        case sqliteError(String)
        case unsupportedCollection(String)
        case emptyCollection
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "The specified .apkg file was not found."
            case .invalidZipArchive:
                return "Failed to decompress the .apkg archive. The file may be corrupt or encrypted."
            case .missingCollectionDatabase:
                return "Invalid .apkg format: missing collection.anki2 database inside archive."
            case .sqliteError(let msg):
                return "SQLite database error: \(msg)"
            case .unsupportedCollection(let msg):
                return msg
            case .emptyCollection:
                return "The .apkg package contains no importable cards or decks."
            }
        }
    }
    
    // MARK: - Main Import Entrypoint
    
    static func importApkg(from fileURL: URL, into context: ModelContext) throws -> ApkgImportResult {
        // 1. Create a isolated temporary extraction directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("apkg_extract_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // 2. Unzip the .apkg file into tempDir
        try unzipArchive(at: fileURL, to: tempDir)
        
        // 3. Locate collection.anki2 or collection.anki21 SQLite database
        let dbURL = tempDir.appendingPathComponent("collection.anki2")
        let db21URL = tempDir.appendingPathComponent("collection.anki21")
        let db21bURL = tempDir.appendingPathComponent("collection.anki21b")
        let targetDBURL: URL?
        if FileManager.default.fileExists(atPath: dbURL.path) {
            targetDBURL = dbURL
        } else if FileManager.default.fileExists(atPath: db21URL.path) {
            targetDBURL = db21URL
        } else if FileManager.default.fileExists(atPath: db21bURL.path) {
            let compressed = try Data(contentsOf: db21bURL)
            let sqlite = try decompressZstd(compressed)
            guard sqlite.starts(with: Data("SQLite format 3".utf8)) else {
                throw ApkgError.unsupportedCollection("Decompressed collection.anki21b, but it is not a SQLite database.")
            }
            let decodedURL = tempDir.appendingPathComponent("collection.anki21b.sqlite")
            try sqlite.write(to: decodedURL)
            targetDBURL = decodedURL
        } else {
            targetDBURL = nil
        }
        
        guard let databaseURL = targetDBURL else {
            throw ApkgError.missingCollectionDatabase
        }
        
        // 4. Extract and import media assets
        let mediaFilesImported = importMediaAssets(from: tempDir)
        
        // 5. Read SQLite database and populate SwiftData
        let (decksCreated, cardsImported, deckNames) = try readSQLiteAndPopulate(databaseURL: databaseURL, in: context)
        
        try context.save()
        
        let message = "Successfully imported \(cardsImported) cards across \(decksCreated) decks (\(mediaFilesImported) media files extracted) from '\(fileURL.lastPathComponent)'."
        
        return ApkgImportResult(
            decksCount: decksCreated,
            cardsCount: cardsImported,
            mediaFilesCount: mediaFilesImported,
            deckNames: deckNames,
            message: message
        )
    }
    
    // MARK: - Media Extraction
    
    private static func importMediaAssets(from dir: URL) -> Int {
        let mediaMapURL = dir.appendingPathComponent("media")
        guard let mediaData = try? Data(contentsOf: mediaMapURL),
              let json = try? JSONSerialization.jsonObject(with: mediaData) as? [String: String] else {
            return 0
        }
        
        var count = 0
        for (internalName, actualFilename) in json {
            let sourceFileURL = dir.appendingPathComponent(internalName)
            if FileManager.default.fileExists(atPath: sourceFileURL.path) {
                do {
                    try MediaManager.shared.copyMediaFile(from: sourceFileURL, named: actualFilename)
                    count += 1
                } catch {
                    print("Failed to save media '\(actualFilename)': \(error.localizedDescription)")
                }
            }
        }
        return count
    }
    
    // MARK: - SQLite Parser
    
    private static func readSQLiteAndPopulate(databaseURL: URL, in context: ModelContext) throws -> (decksCount: Int, cardsCount: Int, deckNames: [String]) {
        var db: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw ApkgError.sqliteError(errmsg)
        }
        defer {
            sqlite3_close(db)
        }
        
        // 1. Read Decks JSON from 'col' table
        var deckNameByID: [Int64: String] = [:]
        var queryCol = "SELECT decks FROM col LIMIT 1"
        var stmtCol: OpaquePointer?
        if sqlite3_prepare_v2(db, queryCol, -1, &stmtCol, nil) == SQLITE_OK {
            if sqlite3_step(stmtCol) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmtCol, 0) {
                    let jsonString = String(cString: cStr)
                    if let data = jsonString.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                        for (idStr, dict) in obj {
                            if let id = Int64(idStr), let name = dict["name"] as? String {
                                deckNameByID[id] = name
                            }
                        }
                    }
                }
            }
        }
        sqlite3_finalize(stmtCol)

        if deckNameByID.isEmpty {
            var stmtDecks: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT id, name FROM decks", -1, &stmtDecks, nil) == SQLITE_OK {
                while sqlite3_step(stmtDecks) == SQLITE_ROW {
                    let id = sqlite3_column_int64(stmtDecks, 0)
                    if let cStr = sqlite3_column_text(stmtDecks, 1) {
                        deckNameByID[id] = String(cString: cStr)
                    }
                }
            }
            sqlite3_finalize(stmtDecks)
        }
        
        // Ensure at least one deck exists
        if deckNameByID.isEmpty {
            deckNameByID[1] = "Default"
        }
        
        // Map deck names to SwiftData Deck entities
        var swiftDataDecks: [Int64: Deck] = [:]
        let existingDecksDescriptor = FetchDescriptor<Deck>()
        let existingDecks = (try? context.fetch(existingDecksDescriptor)) ?? []
        
        var createdDecksCount = 0
        var deckNamesList: [String] = []
        
        for (did, name) in deckNameByID {
            if name == "Default" && deckNameByID.count > 1 { continue }
            deckNamesList.append(name)
            if let existing = existingDecks.first(where: { $0.name == name }) {
                swiftDataDecks[did] = existing
            } else {
                let newDeck = Deck(name: name, deckDescription: "Imported from Anki .apkg")
                context.insert(newDeck)
                swiftDataDecks[did] = newDeck
                createdDecksCount += 1
            }
        }
        
        // 2. Read Notes: note_id -> (flds, tags)
        struct NoteInfo {
            let flds: String
            let tags: String
        }
        var notesByID: [Int64: NoteInfo] = [:]
        let queryNotes = "SELECT id, flds, tags FROM notes"
        var stmtNotes: OpaquePointer?
        if sqlite3_prepare_v2(db, queryNotes, -1, &stmtNotes, nil) == SQLITE_OK {
            while sqlite3_step(stmtNotes) == SQLITE_ROW {
                let nid = sqlite3_column_int64(stmtNotes, 0)
                let flds = sqlite3_column_text(stmtNotes, 1).map { String(cString: $0) } ?? ""
                let tags = sqlite3_column_text(stmtNotes, 2).map { String(cString: $0) } ?? ""
                notesByID[nid] = NoteInfo(flds: flds, tags: tags)
            }
        }
        sqlite3_finalize(stmtNotes)
        
        // 3. Read Cards: card_id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses
        let queryCards = "SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses FROM cards"
        var stmtCards: OpaquePointer?
        var importedCardsCount = 0
        
        // Index existing cards per deck to prevent duplicate creation on re-import
        var existingCardsByDeckID: [Int64: [String: Card]] = [:]
        for (did, deck) in swiftDataDecks {
            var cardMap: [String: Card] = [:]
            for card in deck.cards {
                let key = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
                cardMap[key] = card
            }
            existingCardsByDeckID[did] = cardMap
        }
        
        if sqlite3_prepare_v2(db, queryCards, -1, &stmtCards, nil) == SQLITE_OK {
            while sqlite3_step(stmtCards) == SQLITE_ROW {
                let nid = sqlite3_column_int64(stmtCards, 1)
                let did = sqlite3_column_int64(stmtCards, 2)
                let ivl = sqlite3_column_int(stmtCards, 7)
                let factor = sqlite3_column_int(stmtCards, 8)
                let reps = sqlite3_column_int(stmtCards, 9)
                let lapses = sqlite3_column_int(stmtCards, 10)
                
                guard let note = notesByID[nid] else { continue }
                
                // Fields in Anki are delimited by ASCII 31 (0x1f)
                let fieldComponents = note.flds.components(separatedBy: "\u{1f}")
                let frontText = fieldComponents.first ?? ""
                let backText = fieldComponents.count > 1 ? fieldComponents[1] : ""
                let extraText = fieldComponents.count > 2 ? fieldComponents[2] : ""
                
                // Extract tags (space-separated in Anki)
                let tagList = note.tags
                    .components(separatedBy: " ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                // Determine NoteType
                let noteType: NoteType = frontText.contains("{{c") ? .cloze : .basic
                
                // Resolve target Deck
                let targetDeck = swiftDataDecks[did] ?? swiftDataDecks.values.first ?? {
                    let d = Deck(name: "Imported Decks")
                    context.insert(d)
                    return d
                }()
                
                let trimmedFront = frontText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let existingCard = existingCardsByDeckID[did]?[trimmedFront] {
                    // Card already exists in this deck: update properties and avoid duplicates
                    existingCard.back = backText
                    existingCard.extra = extraText
                    for tag in tagList where !existingCard.tags.contains(tag) {
                        existingCard.tags.append(tag)
                    }
                    if Int(reps) > existingCard.repetitions {
                        existingCard.repetitions = Int(reps)
                        existingCard.interval = Double(ivl)
                        existingCard.lapseCount = Int(lapses)
                        if factor > 0 {
                            existingCard.easeFactor = Double(factor) / 1000.0
                        }
                    }
                    importedCardsCount += 1
                    continue
                }
                
                // Construct and insert new Card
                let card = Card(
                    front: frontText,
                    back: backText,
                    deck: targetDeck,
                    tags: tagList,
                    noteTypeRaw: noteType.rawValue,
                    lapseCount: Int(lapses),
                    interval: Double(ivl),
                    easeFactor: factor > 0 ? (Double(factor) / 1000.0) : 2.5,
                    repetitions: Int(reps),
                    stateRaw: ivl > 0 ? CardState.review.rawValue : (reps > 0 ? CardState.learning.rawValue : CardState.new.rawValue),
                    extra: extraText
                )
                
                context.insert(card)
                targetDeck.cards.append(card)
                if existingCardsByDeckID[did] != nil {
                    existingCardsByDeckID[did]?[trimmedFront] = card
                } else {
                    existingCardsByDeckID[did] = [trimmedFront: card]
                }
                importedCardsCount += 1
            }
        }
        sqlite3_finalize(stmtCards)
        
        if importedCardsCount == 0 {
            throw ApkgError.emptyCollection
        }
        
        return (createdDecksCount, importedCardsCount, deckNamesList)
    }
    
    // MARK: - ZIP Decompression Engine
    
    private static func unzipArchive(at sourceURL: URL, to destinationURL: URL) throws {
        try pureSwiftUnzip(sourceURL: sourceURL, destinationURL: destinationURL)
    }
    
    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        return b0 | (b1 << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    /// Pure Swift ZIP entry parser. Handles stored files, raw deflate, and data descriptors.
    private static func pureSwiftUnzip(sourceURL: URL, destinationURL: URL) throws {
        guard let data = try? Data(contentsOf: sourceURL) else {
            throw ApkgError.fileNotFound
        }

        var offset = 0
        let count = data.count

        while offset + 30 <= count {
            let sig = readUInt32(data, offset)
            if sig != 0x04034b50 { break }

            let flags = readUInt16(data, offset + 6)
            let method = readUInt16(data, offset + 8)
            var compSize = Int(readUInt32(data, offset + 18))
            var uncompSize = Int(readUInt32(data, offset + 22))
            let nameLen = Int(readUInt16(data, offset + 26))
            let extraLen = Int(readUInt16(data, offset + 28))

            let headerSize = 30 + nameLen + extraLen
            guard offset + headerSize <= count else { break }

            let nameData = data.subdata(in: (offset + 30)..<(offset + 30 + nameLen))
            let filename = String(data: nameData, encoding: .utf8) ?? "file_\(offset)"
            let dataStart = offset + headerSize

            var dataEnd = dataStart + compSize
            if (flags & 0x8) != 0 && compSize == 0 {
                guard let located = locateDataDescriptor(data: data, from: dataStart) else { break }
                compSize = located.compSize
                uncompSize = located.uncompSize
                dataEnd = located.dataEnd
            }
            guard dataEnd <= count, dataStart <= dataEnd else { break }

            let compData = data.subdata(in: dataStart..<dataEnd)
            let outURL = destinationURL.appendingPathComponent(filename)
            if filename.hasSuffix("/") {
                try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
            } else if method == 0 {
                try? compData.write(to: outURL)
            } else if method == 8 {
                if let decompressed = decompressDeflate(data: compData, uncompressedSize: uncompSize > 0 ? uncompSize : max(compData.count * 4, 64)) {
                    try? decompressed.write(to: outURL)
                }
            }

            offset = dataEnd
            if (flags & 0x8) != 0 && readUInt32(data, offset) == 0x08074b50 {
                offset += 16
            } else if (flags & 0x8) != 0 {
                offset += 12
            }
        }
    }

    private static func locateDataDescriptor(data: Data, from start: Int) -> (compSize: Int, uncompSize: Int, dataEnd: Int)? {
        var scan = start
        let count = data.count
        while scan + 4 <= count {
            let sig = readUInt32(data, scan)
            if sig == 0x04034b50 || sig == 0x02014b50 {
                if scan >= start + 16 && readUInt32(data, scan - 16) == 0x08074b50 {
                    let comp = Int(readUInt32(data, scan - 8))
                    let uncomp = Int(readUInt32(data, scan - 4))
                    return (comp, uncomp, scan - 16)
                }
                if scan >= start + 12 {
                    let comp = Int(readUInt32(data, scan - 8))
                    let uncomp = Int(readUInt32(data, scan - 4))
                    return (comp, uncomp, scan - 12)
                }
                return nil
            }
            scan += 1
        }
        return nil
    }

    private static func decompressDeflate(data: Data, uncompressedSize: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = max(uncompressedSize, data.count * 4, 64)
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { output.deallocate() }

        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let decoded: Int = data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            stream.next_out = output
            stream.avail_out = uInt(capacity)
            let result = inflate(&stream, Z_FINISH)
            guard result == Z_STREAM_END || result == Z_OK else { return -1 }
            return capacity - Int(stream.avail_out)
        }
        guard decoded > 0 else { return nil }
        return Data(bytes: output, count: decoded)
    }

    private static func decompressZstd(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw ApkgError.unsupportedCollection("The collection.anki21b file is empty.")
            }
            var outPtr: UnsafeMutableRawPointer?
            var outSize = 0
            var err = [CChar](repeating: 0, count: 180)
            let rc = recallrx_zstd_decompress(base, data.count, &outPtr, &outSize, &err, err.count)
            guard rc == 0, let outPtr, outSize > 0 else {
                let message = String(cString: err)
                throw ApkgError.unsupportedCollection(message.isEmpty ? "Could not decompress collection.anki21b." : message)
            }
            defer { free(outPtr) }
            return Data(bytes: outPtr, count: outSize)
        }
    }
}
