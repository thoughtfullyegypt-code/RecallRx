import Foundation
import SQLite3

/// A fully validated, detached snapshot. Parsing never mutates the study library.
struct AnkiImportPackage {
    struct Template {
        let question: String
        let answer: String
    }

    struct NoteModel {
        var fieldNames: [String]
        var templates: [Int: Template]
        var isCloze: Bool
        var css: String
    }

    struct Note {
        let id: Int64
        let guid: String
        let modelID: Int64
        let fields: [String]
        let tags: [String]
        let modified: Date
    }

    struct ImportedCard {
        let id: Int64
        let noteID: Int64
        let deckID: Int64
        let ordinal: Int
        let type: Int
        let queue: Int
        let due: Int64
        let interval: Int
        let factor: Int
        let repetitions: Int
        let lapses: Int
        let remainingSteps: Int
        let modified: Date
        let lastReview: Date?
        let fsrsStability: Double
        let fsrsDifficulty: Double
    }

    let creationDate: Date
    let deckNames: [Int64: String]
    let models: [Int64: NoteModel]
    let notes: [Int64: Note]
    let cards: [ImportedCard]

    init(databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open collection database."
            sqlite3_close(database)
            throw ApkgImporter.ApkgError.sqliteError(message)
        }
        guard let db = database else { throw ApkgImporter.ApkgError.missingCollectionDatabase }
        defer { sqlite3_close(db) }

        var created: Date?
        var decks: [Int64: String] = [:]
        var modelMap: [Int64: NoteModel] = [:]
        try Self.rows(db, "SELECT crt, decks, models FROM col LIMIT 1") { row in
            created = Date(timeIntervalSince1970: Double(sqlite3_column_int64(row, 0)))
            if let json = try Self.jsonDictionary(Self.text(row, 1)) {
                for (key, value) in json {
                    if let id = Int64(key), let object = value as? [String: Any], let name = object["name"] as? String {
                        decks[id] = name
                    }
                }
            }
            if let json = try Self.jsonDictionary(Self.text(row, 2)) {
                for (key, value) in json {
                    guard let id = Int64(key), let object = value as? [String: Any],
                          let fields = object["flds"] as? [[String: Any]], let templates = object["tmpls"] as? [[String: Any]] else {
                        throw ApkgImporter.ApkgError.invalidMetadata
                    }
                    let orderedFields = fields.sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                    var templateMap: [Int: Template] = [:]
                    for (index, template) in templates.enumerated() {
                        guard let question = template["qfmt"] as? String, let answer = template["afmt"] as? String else {
                            throw ApkgImporter.ApkgError.invalidMetadata
                        }
                        templateMap[template["ord"] as? Int ?? index] = Template(question: question, answer: answer)
                    }
                    modelMap[id] = NoteModel(
                        fieldNames: orderedFields.map { $0["name"] as? String ?? "" },
                        templates: templateMap,
                        isCloze: (object["type"] as? Int ?? 0) == 1,
                        css: object["css"] as? String ?? ""
                    )
                }
            }
        }
        guard let created, created.timeIntervalSince1970 > 0 else {
            throw ApkgImporter.ApkgError.unsupportedCollection("The Anki collection is missing its creation date.")
        }

        if Self.tableExists(db, "decks") {
            try Self.rows(db, "SELECT id, name FROM decks") { row in
                decks[sqlite3_column_int64(row, 0)] = Self.text(row, 1).replacingOccurrences(of: "\u{1f}", with: "::")
            }
        }
        // Schema 16+ stores notetypes, field names, and templates in normalized tables.
        if Self.tableExists(db, "notetypes") {
            try Self.rows(db, "SELECT id, config FROM notetypes") { row in
                let id = sqlite3_column_int64(row, 0)
                let config = try AnkiProtobuf(Self.blob(row, 1))
                modelMap[id] = NoteModel(fieldNames: [], templates: [:], isCloze: config.integers[1]?.first == 1, css: config.string(3) ?? "")
            }
            try Self.rows(db, "SELECT ntid, ord, name FROM fields ORDER BY ntid, ord") { row in
                let id = sqlite3_column_int64(row, 0)
                let ordinal = Int(sqlite3_column_int(row, 1))
                guard ordinal >= 0, ordinal < 1000, modelMap[id] != nil else { throw ApkgImporter.ApkgError.invalidMetadata }
                while modelMap[id]!.fieldNames.count <= ordinal { modelMap[id]!.fieldNames.append("") }
                modelMap[id]!.fieldNames[ordinal] = Self.text(row, 2)
            }
            try Self.rows(db, "SELECT ntid, ord, config FROM templates") { row in
                let id = sqlite3_column_int64(row, 0)
                let config = try AnkiProtobuf(Self.blob(row, 2))
                guard let question = config.string(1), let answer = config.string(2), modelMap[id] != nil else {
                    throw ApkgImporter.ApkgError.invalidMetadata
                }
                modelMap[id]!.templates[Int(sqlite3_column_int(row, 1))] = Template(question: question, answer: answer)
            }
        }

        var noteMap: [Int64: Note] = [:]
        try Self.rows(db, "SELECT id, guid, mid, flds, tags, mod FROM notes") { row in
            let id = sqlite3_column_int64(row, 0)
            guard noteMap[id] == nil else { throw ApkgImporter.ApkgError.invalidMetadata }
            noteMap[id] = Note(
                id: id,
                guid: Self.text(row, 1),
                modelID: sqlite3_column_int64(row, 2),
                fields: Self.text(row, 3).components(separatedBy: "\u{1f}"),
                tags: Self.text(row, 4).split(whereSeparator: \.isWhitespace).map(String.init),
                modified: Date(timeIntervalSince1970: Double(sqlite3_column_int64(row, 5)))
            )
        }
        var lastReviews: [Int64: Date] = [:]
        if Self.tableExists(db, "revlog") {
            try Self.rows(db, "SELECT cid, MAX(id) FROM revlog GROUP BY cid") { row in
                lastReviews[sqlite3_column_int64(row, 0)] = Date(timeIntervalSince1970: Double(sqlite3_column_int64(row, 1)) / 1000)
            }
        }

        let columns = try Self.columns(db, table: "cards")
        let optionalColumns = ["mod", "left", "odue", "odid", "data"].map { columns.contains($0) ? "\"\($0)\"" : "0" }.joined(separator: ", ")
        var cardList: [ImportedCard] = []
        var cardIDs: Set<Int64> = []
        try Self.rows(db, "SELECT id, nid, did, ord, type, queue, due, ivl, factor, reps, lapses, \(optionalColumns) FROM cards ORDER BY id") { row in
            let id = sqlite3_column_int64(row, 0)
            let noteID = sqlite3_column_int64(row, 1)
            guard cardIDs.insert(id).inserted, let note = noteMap[noteID], modelMap[note.modelID] != nil else {
                throw ApkgImporter.ApkgError.unsupportedCollection("An Anki card refers to a missing or unsupported note type.")
            }
            let originalDeck = sqlite3_column_int64(row, 14)
            let originalDue = sqlite3_column_int64(row, 13)
            let deckID = originalDeck != 0 ? originalDeck : sqlite3_column_int64(row, 2)
            let type = Int(sqlite3_column_int(row, 4))
            let queue = Int(sqlite3_column_int(row, 5))
            guard (0...3).contains(type), (-3...4).contains(queue), decks[deckID] != nil else {
                throw ApkgImporter.ApkgError.unsupportedCollection("An Anki card contains an unsupported queue or a missing deck.")
            }
            let customData = try? Self.jsonDictionary(Self.text(row, 15))
            cardList.append(ImportedCard(
                id: id, noteID: noteID, deckID: deckID,
                ordinal: Int(sqlite3_column_int(row, 3)), type: type, queue: queue,
                due: originalDeck != 0 && originalDue != 0 ? originalDue : sqlite3_column_int64(row, 6),
                interval: Int(sqlite3_column_int(row, 7)), factor: Int(sqlite3_column_int(row, 8)),
                repetitions: Int(sqlite3_column_int(row, 9)), lapses: Int(sqlite3_column_int(row, 10)),
                remainingSteps: Int(sqlite3_column_int(row, 12)),
                modified: Date(timeIntervalSince1970: Double(sqlite3_column_int64(row, 11))),
                lastReview: lastReviews[id],
                fsrsStability: customData?["s"] as? Double ?? 0,
                fsrsDifficulty: customData?["d"] as? Double ?? 0
            ))
        }
        guard !cardList.isEmpty else { throw ApkgImporter.ApkgError.emptyCollection }
        creationDate = created
        deckNames = decks
        models = modelMap
        notes = noteMap
        cards = cardList
    }

    private static func rows(_ db: OpaquePointer, _ query: String, _ consume: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ApkgImporter.ApkgError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw ApkgImporter.ApkgError.sqliteError(String(cString: sqlite3_errmsg(db))) }
            try consume(statement)
        }
    }

    private static func text(_ row: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(row, index).map { String(cString: $0) } ?? ""
    }

    private static func blob(_ row: OpaquePointer, _ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(row, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, index)))
    }

    private static func jsonDictionary(_ text: String) throws -> [String: Any]? {
        guard !text.isEmpty else { return nil }
        guard let data = text.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApkgImporter.ApkgError.invalidMetadata
        }
        return json
    }

    private static func tableExists(_ db: OpaquePointer, _ table: String) -> Bool {
        var exists = false
        try? rows(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='\(table)'") { _ in exists = true }
        return exists
    }

    private static func columns(_ db: OpaquePointer, table: String) throws -> Set<String> {
        var names: Set<String> = []
        try rows(db, "PRAGMA table_info(\(table))") { row in names.insert(text(row, 1)) }
        return names
    }
}
