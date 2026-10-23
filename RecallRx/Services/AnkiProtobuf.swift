import Foundation

/// Minimal protobuf wire reader for Anki's documented notetype and media metadata.
/// Unknown fields are skipped so newer optional metadata does not break imports.
struct AnkiProtobuf {
    let bytes: [UInt8]
    private(set) var fields: [Int: [Data]] = [:]
    private(set) var integers: [Int: [UInt64]] = [:]

    init(_ data: Data) throws {
        bytes = Array(data)
        var offset = 0
        while offset < bytes.count {
            let key = try Self.varint(bytes, offset: &offset)
            let number = Int(key >> 3)
            guard number > 0 else { throw ApkgImporter.ApkgError.invalidMetadata }
            switch key & 7 {
            case 0:
                integers[number, default: []].append(try Self.varint(bytes, offset: &offset))
            case 1:
                guard offset + 8 <= bytes.count else { throw ApkgImporter.ApkgError.invalidMetadata }
                offset += 8
            case 2:
                let length = try Self.varint(bytes, offset: &offset)
                guard length <= UInt64(bytes.count - offset) else { throw ApkgImporter.ApkgError.invalidMetadata }
                let end = offset + Int(length)
                fields[number, default: []].append(Data(bytes[offset..<end]))
                offset = end
            case 5:
                guard offset + 4 <= bytes.count else { throw ApkgImporter.ApkgError.invalidMetadata }
                offset += 4
            default:
                throw ApkgImporter.ApkgError.invalidMetadata
            }
        }
    }

    func string(_ number: Int) -> String? {
        fields[number]?.first.flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func varint(_ bytes: [UInt8], offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard offset < bytes.count else { throw ApkgImporter.ApkgError.invalidMetadata }
            let byte = bytes[offset]
            offset += 1
            guard shift < 63 || byte <= 1 else { throw ApkgImporter.ApkgError.invalidMetadata }
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
        }
        throw ApkgImporter.ApkgError.invalidMetadata
    }
}
