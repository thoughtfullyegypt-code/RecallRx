import Foundation
import SQLite3
import SwiftData
import XCTest
import zlib
@testable import RecallRx

final class AnkiImportRegressionTests: XCTestCase {
    @MainActor
    func testReverseCardsIdenticalPromptsAndRepeatedImportKeepSeparateIdentities() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let archive = try fixture.archive(
            notes: [Note(id: 1100, fields: ["Shared question", "First answer", "Reference"]),
                    Note(id: 1200, fields: ["Shared question", "Different answer", ""])],
            cards: [SourceCard(id: 2100, note: 1100), SourceCard(id: 2101, note: 1100, ordinal: 1), SourceCard(id: 2102, note: 1200)]
        )
        let first = try fixture.importArchive(archive)
        XCTAssertEqual(first.cardsCount, 3)
        let cards = try fixture.cards()
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(cards.filter { $0.front == "Shared question" }.count, 2)
        XCTAssertTrue(cards.contains { $0.front == "First answer" && $0.back.contains("Shared question") })
        XCTAssertTrue(cards.contains { $0.front == "Shared question" && $0.back.contains("Different answer") })
        let identities = Set(cards.map(\.id))

        let second = try fixture.importArchive(archive)
        XCTAssertEqual(second.cardsCount, 0)
        XCTAssertEqual(second.updatedCardsCount, 3)
        XCTAssertEqual(Set(try fixture.cards().map(\.id)), identities)
    }

    @MainActor
    func testEachAnkiClozeOrdinalHidesOnlyItsOwnDeletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let archive = try fixture.archive(
            notes: [Note(id: 1100, model: 200, fields: ["The mitral valve separates {{c1::left atrium}} from {{c2::left ventricle}}.", "Clinical context"])],
            cards: [SourceCard(id: 2100, note: 1100), SourceCard(id: 2101, note: 1100, ordinal: 1)]
        )
        XCTAssertEqual(try fixture.importArchive(archive).cardsCount, 2)
        let cards = try fixture.cards()
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.contains { $0.front.contains("{{c1::left atrium}}") && !$0.front.contains("{{c2::") })
        XCTAssertTrue(cards.contains { $0.front.contains("{{c1::left ventricle}}") && !$0.front.contains("{{c1::left atrium}}") })
        XCTAssertTrue(cards.allSatisfy { $0.back.contains("left atrium") && $0.back.contains("left ventricle") })
        XCTAssertTrue(cards.allSatisfy { $0.noteType == .cloze })
    }

    @MainActor
    func testImportPreservesFutureDatesSuspensionBurialAndLearningQueues() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let secondsDue = Int64(Date().timeIntervalSince1970) + 90
        let archive = try fixture.archive(
            notes: [Note(id: 1100, fields: ["Question", "Answer", ""])],
            cards: [
                SourceCard(id: 2100, note: 1100, type: 2, queue: 2, due: 500, interval: 30, repetitions: 12),
                SourceCard(id: 2101, note: 1100, type: 2, queue: -1, due: 501, interval: 31, repetitions: 9),
                SourceCard(id: 2102, note: 1100, type: 2, queue: -3, due: 502, interval: 32, repetitions: 8),
                SourceCard(id: 2103, note: 1100, type: 1, queue: 1, due: secondsDue, interval: -90, repetitions: 1),
                SourceCard(id: 2104, note: 1100, type: 3, queue: 3, due: 503, interval: 7, repetitions: 4)
            ]
        )
        _ = try fixture.importArchive(archive)
        let cards = try fixture.cards()
        XCTAssertEqual(cards.count, 5)
        let review = try XCTUnwrap(cards.first { $0.repetitions == 12 })
        let expected = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 500, to: Fixture.creationDate))
        XCTAssertEqual(review.dueDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(review.state, .review)
        XCTAssertEqual(review.interval, 30)
        XCTAssertEqual(review.easeFactor, 2.6)
        XCTAssertTrue(try XCTUnwrap(cards.first { $0.repetitions == 9 }).isSuspended)
        let buried = try XCTUnwrap(cards.first { $0.repetitions == 8 })
        XCTAssertTrue(buried.isBuried)
        XCTAssertGreaterThan(try XCTUnwrap(buried.buriedUntil), Date())
        let learning = try XCTUnwrap(cards.first { $0.state == .learning })
        XCTAssertEqual(learning.dueDate.timeIntervalSince1970, Double(secondsDue), accuracy: 1)
        XCTAssertEqual(learning.interval, 90.0 / 86_400, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(cards.first { $0.state == .relearning }).interval, 7)
    }

    @MainActor
    func testReimportDoesNotUndoLocalSchedulingOrSuspension() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let archive = try fixture.archive(notes: [Note(id: 1100, fields: ["Question", "Answer", ""])], cards: [SourceCard(id: 2100, note: 1100)])
        _ = try fixture.importArchive(archive)
        let context = ModelContext(fixture.container)
        let card = try XCTUnwrap(context.fetch(FetchDescriptor<Card>()).first)
        let localDue = Date(timeIntervalSince1970: 3_000_000_000)
        card.repetitions = 99
        card.dueDate = localDue
        card.isSuspended = true
        card.modifiedAt = Date()
        try context.save()
        _ = try fixture.importArchive(archive)
        let preserved = try XCTUnwrap(fixture.cards().first)
        XCTAssertEqual(preserved.repetitions, 99)
        XCTAssertEqual(preserved.dueDate, localDue)
        XCTAssertTrue(preserved.isSuspended)
    }

    @MainActor
    func testMediaCollisionKeepsOldImageAndRewritesImportedReferences() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("existing image".utf8)
        let incoming = Data("new image".utf8)
        try original.write(to: fixture.media.appendingPathComponent("diagram.png"))
        let archive = try fixture.archive(
            notes: [Note(id: 1100, fields: ["Identify <img src=\"diagram.png\">", "Answer [sound:heart.mp3]", ""])],
            cards: [SourceCard(id: 2100, note: 1100)],
            media: ["diagram.png": incoming, "heart.mp3": Data("audio".utf8)]
        )
        let result = try fixture.importArchive(archive)
        XCTAssertEqual(result.mediaFilesCount, 2)
        XCTAssertEqual(try Data(contentsOf: fixture.media.appendingPathComponent("diagram.png")), original)
        let card = try XCTUnwrap(fixture.cards().first)
        XCTAssertTrue(card.front.contains("diagram_anki_"))
        let renamed = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: fixture.media.path).first { $0.hasPrefix("diagram_anki_") })
        XCTAssertEqual(try Data(contentsOf: fixture.media.appendingPathComponent(renamed)), incoming)
        XCTAssertEqual(try Data(contentsOf: fixture.media.appendingPathComponent("heart.mp3")), Data("audio".utf8))
        let repeatResult = try fixture.importArchive(archive)
        XCTAssertEqual(repeatResult.cardsCount, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.media.path).count, 3)
    }

    @MainActor
    func testUnsupportedTemplateRollsBackModelsAndLeavesExistingMediaUntouched() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("existing".utf8)
        try original.write(to: fixture.media.appendingPathComponent("diagram.png"))
        let archive = try fixture.archive(
            notes: [Note(id: 1100, fields: ["Question", "Answer", ""])],
            cards: [SourceCard(id: 2100, note: 1100, ordinal: 99)],
            media: ["diagram.png": Data("replacement".utf8)]
        )
        XCTAssertThrowsError(try fixture.importArchive(archive))
        XCTAssertEqual(try fixture.cards().count, 0)
        XCTAssertEqual(try ModelContext(fixture.container).fetchCount(FetchDescriptor<Deck>()), 0)
        XCTAssertEqual(try Data(contentsOf: fixture.media.appendingPathComponent("diagram.png")), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.media.path), ["diagram.png"])
    }

    @MainActor
    func testUnsafeArchiveAndMediaPathsFailWithoutWritingOutsideDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let archive = fixture.root.appendingPathComponent("unsafe.apkg")
        try Fixture.zip([("../escaped", Data("bad".utf8))]).write(to: archive)
        XCTAssertThrowsError(try fixture.importArchive(archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.deletingLastPathComponent().appendingPathComponent("escaped").path))
        let manager = MediaManager(mediaDirectoryURL: fixture.media)
        XCTAssertThrowsError(try manager.saveMedia(data: Data(), named: "../escaped"))
        XCTAssertNil(manager.getMediaURL(for: "%2E%2E/escaped"))
    }

    @MainActor
    func testCollectionAnki21IsChosenOverLegacyCompatibilityStub() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let archive = try fixture.archive(
            notes: [Note(id: 1100, fields: ["Actual question", "Actual answer", ""])],
            cards: [SourceCard(id: 2100, note: 1100)],
            databaseName: "collection.anki21", includeCompatibilityStub: true
        )
        XCTAssertEqual(try fixture.importArchive(archive).cardsCount, 1)
        XCTAssertEqual(try fixture.cards().first?.front, "Actual question")
    }

    @MainActor
    func testModernZstdCollectionNormalizedTemplatesAndProtobufMedia() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let image = Data("modern image".utf8)
        let archive = try fixture.archive(
            notes: [Note(id: 1100, fields: ["Modern <img src=\"diagram.png\">", "Answer", ""])],
            cards: [SourceCard(id: 2100, note: 1100), SourceCard(id: 2101, note: 1100, ordinal: 1)],
            media: ["diagram.png": image], includeCompatibilityStub: true, modern: true
        )
        XCTAssertEqual(try fixture.importArchive(archive).cardsCount, 2)
        let cards = try fixture.cards()
        XCTAssertTrue(cards.contains { $0.front == "Answer" })
        XCTAssertTrue(cards.contains { $0.front.contains("Modern") })
        XCTAssertEqual(try Data(contentsOf: fixture.media.appendingPathComponent("diagram.png")), image)
    }

    private struct Note {
        let id: Int64
        var model: Int64 = 100
        let fields: [String]
    }

    private struct SourceCard {
        let id: Int64
        let note: Int64
        var ordinal = 0
        var type = 0
        var queue = 0
        var due: Int64 = 0
        var interval = 0
        var repetitions = 0
    }

    @MainActor
    private final class Fixture {
        static let creationDate = Date(timeIntervalSince1970: 1_767_225_600)
        let root: URL
        let media: URL
        let container: ModelContainer

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("anki_test_\(UUID().uuidString)")
            media = root.appendingPathComponent("media", isDirectory: true)
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
            let schema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        func cards() throws -> [Card] { try ModelContext(container).fetch(FetchDescriptor<Card>()) }

        func importArchive(_ url: URL) throws -> ApkgImporter.ApkgImportResult {
            try ApkgImporter.importApkg(from: url, into: container.mainContext, mediaDirectoryURL: media)
        }

        func archive(notes: [Note], cards: [SourceCard], media: [String: Data] = [:], databaseName: String = "collection.anki2", includeCompatibilityStub: Bool = false, modern: Bool = false) throws -> URL {
            let databaseURL = root.appendingPathComponent("fixture.sqlite")
            try? FileManager.default.removeItem(at: databaseURL)
            var database: OpaquePointer?
            guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
                throw NSError(domain: "AnkiFixture", code: 1)
            }
            do {
                try execute(database, "CREATE TABLE col (crt INTEGER, decks TEXT, models TEXT)")
                try execute(database, "CREATE TABLE notes (id INTEGER PRIMARY KEY, guid TEXT, mid INTEGER, flds TEXT, tags TEXT, mod INTEGER)")
                try execute(database, "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER, did INTEGER, ord INTEGER, type INTEGER, queue INTEGER, due INTEGER, ivl INTEGER, factor INTEGER, reps INTEGER, lapses INTEGER, mod INTEGER, left INTEGER, odue INTEGER, odid INTEGER, data TEXT)")
                try execute(database, "CREATE TABLE revlog (id INTEGER, cid INTEGER)")
                let models: [String: Any] = [
                    "100": ["type": 0, "flds": [["name": "Front", "ord": 0], ["name": "Back", "ord": 1], ["name": "Extra", "ord": 2]],
                            "tmpls": [["ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr>{{Back}}"], ["ord": 1, "qfmt": "{{Back}}", "afmt": "{{Front}}"]]],
                    "200": ["type": 1, "flds": [["name": "Text", "ord": 0], ["name": "Extra", "ord": 1]],
                            "tmpls": [["ord": 0, "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}<br>{{Extra}}"]]]
                ]
                let modelJSON = String(decoding: try JSONSerialization.data(withJSONObject: models), as: UTF8.self)
                try execute(database, "INSERT INTO col VALUES (\(Int(Self.creationDate.timeIntervalSince1970)), '{\"1\":{\"name\":\"Fixture deck\"}}', \(quote(modelJSON)))")
                if modern {
                    try execute(database, "UPDATE col SET models = '{}'")
                    try execute(database, "CREATE TABLE notetypes (id INTEGER, config BLOB)")
                    try execute(database, "CREATE TABLE fields (ntid INTEGER, ord INTEGER, name TEXT)")
                    try execute(database, "CREATE TABLE templates (ntid INTEGER, ord INTEGER, config BLOB)")
                    for (modelID, rawModel) in models {
                        let model = rawModel as! [String: Any]
                        let kind = model["type"] as! Int
                        try execute(database, "INSERT INTO notetypes VALUES (\(modelID), X'\(hex(Data([0x08, UInt8(kind)])))')")
                        for field in model["flds"] as! [[String: Any]] {
                            try execute(database, "INSERT INTO fields VALUES (\(modelID), \(field["ord"] as! Int), \(quote(field["name"] as! String)))")
                        }
                        for template in model["tmpls"] as! [[String: Any]] {
                            let config = Self.protobufField(1, Data((template["qfmt"] as! String).utf8)) + Self.protobufField(2, Data((template["afmt"] as! String).utf8))
                            try execute(database, "INSERT INTO templates VALUES (\(modelID), \(template["ord"] as! Int), X'\(hex(config))')")
                        }
                    }
                }
                for note in notes {
                    try execute(database, "INSERT INTO notes VALUES (\(note.id), 'guid-\(note.id)', \(note.model), \(quote(note.fields.joined(separator: "\u{1f}"))), 'Cardiology QID_123', 1700000000)")
                }
                for card in cards {
                    try execute(database, "INSERT INTO cards VALUES (\(card.id), \(card.note), 1, \(card.ordinal), \(card.type), \(card.queue), \(card.due), \(card.interval), 2600, \(card.repetitions), 2, 1700000000, 1002, 0, 0, '{}')")
                }
            } catch {
                sqlite3_close(database)
                throw error
            }
            sqlite3_close(database)
            let databaseData = try Data(contentsOf: databaseURL)
            var entries: [(String, Data)] = [(modern ? "collection.anki21b" : databaseName, modern ? Self.zstdRawFrame(databaseData) : databaseData)]
            if includeCompatibilityStub { entries.append(("collection.anki2", Data("compatibility stub".utf8))) }
            var mediaMap: [String: String] = [:]
            for (index, entry) in media.sorted(by: { $0.key < $1.key }).enumerated() {
                entries.append((String(index), modern ? Self.zstdRawFrame(entry.value) : entry.value))
                mediaMap[String(index)] = entry.key
            }
            if modern {
                var message = Data()
                for entry in media.sorted(by: { $0.key < $1.key }) {
                    message.append(Self.protobufField(1, Self.protobufField(1, Data(entry.key.utf8))))
                }
                entries.append(("media", Self.zstdRawFrame(message)))
            } else {
                entries.append(("media", try JSONSerialization.data(withJSONObject: mediaMap)))
            }
            let output = root.appendingPathComponent("fixture.apkg")
            try Self.zip(entries).write(to: output)
            return output
        }

        private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

        private static func protobufField(_ number: UInt8, _ contents: Data) -> Data {
            var result = Data([number << 3 | 2])
            var count = contents.count
            repeat {
                let byte = UInt8(count & 0x7f)
                count >>= 7
                result.append(count == 0 ? byte : byte | 0x80)
            } while count != 0
            result.append(contents)
            return result
        }

        /// A valid Zstandard frame using uncompressed raw blocks, so tests need no compression dependency.
        private static func zstdRawFrame(_ contents: Data) -> Data {
            var result = Data([0x28, 0xb5, 0x2f, 0xfd, 0xa0])
            var length = UInt32(contents.count).littleEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            var offset = 0
            repeat {
                let blockSize = min(128 * 1024, contents.count - offset)
                let last = offset + blockSize == contents.count
                let header = (UInt32(blockSize) << 3) | (last ? 1 : 0)
                result.append(UInt8(header & 0xff))
                result.append(UInt8((header >> 8) & 0xff))
                result.append(UInt8((header >> 16) & 0xff))
                result.append(contents.subdata(in: offset..<(offset + blockSize)))
                offset += blockSize
            } while offset < contents.count
            return result
        }

        private func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }

        private func execute(_ database: OpaquePointer, _ sql: String) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "AnkiFixture", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
            }
        }

        /// A real stored ZIP with local headers, CRCs, central directory, and EOCD.
        static func zip(_ entries: [(String, Data)]) -> Data {
            var archive = Data()
            var central = Data()
            func number<T: FixedWidthInteger>(_ value: T) -> Data {
                var little = value.littleEndian
                return withUnsafeBytes(of: &little) { Data($0) }
            }
            for (name, contents) in entries {
                let nameData = Data(name.utf8)
                let checksum = contents.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(contents.count)) }
                let position = archive.count
                archive.append(number(UInt32(0x04034b50)))
                archive.append(number(UInt16(20))); archive.append(number(UInt16(0))); archive.append(number(UInt16(0)))
                archive.append(number(UInt16(0))); archive.append(number(UInt16(0))); archive.append(number(UInt32(checksum)))
                archive.append(number(UInt32(contents.count))); archive.append(number(UInt32(contents.count)))
                archive.append(number(UInt16(nameData.count))); archive.append(number(UInt16(0)))
                archive.append(nameData); archive.append(contents)
                central.append(number(UInt32(0x02014b50)))
                central.append(number(UInt16(20))); central.append(number(UInt16(20))); central.append(number(UInt16(0))); central.append(number(UInt16(0)))
                central.append(number(UInt16(0))); central.append(number(UInt16(0))); central.append(number(UInt32(checksum)))
                central.append(number(UInt32(contents.count))); central.append(number(UInt32(contents.count)))
                central.append(number(UInt16(nameData.count))); central.append(number(UInt16(0))); central.append(number(UInt16(0)))
                central.append(number(UInt16(0))); central.append(number(UInt16(0))); central.append(number(UInt32(0)))
                central.append(number(UInt32(position))); central.append(nameData)
            }
            let centralPosition = archive.count
            archive.append(central)
            archive.append(number(UInt32(0x06054b50)))
            archive.append(number(UInt16(0))); archive.append(number(UInt16(0)))
            archive.append(number(UInt16(entries.count))); archive.append(number(UInt16(entries.count)))
            archive.append(number(UInt32(central.count))); archive.append(number(UInt32(centralPosition))); archive.append(number(UInt16(0)))
            return archive
        }
    }
}
