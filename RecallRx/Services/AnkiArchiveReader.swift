import Foundation
import zlib

/// Reads the ZIP central directory, which supplies trustworthy sizes even for data-descriptor entries.
struct AnkiArchiveReader {
    static func extract(_ archive: URL, to directory: URL) throws {
        let data: Data
        do { data = try Data(contentsOf: archive, options: .mappedIfSafe) }
        catch { throw ApkgImporter.ApkgError.fileNotFound }
        guard data.count >= 22 else { throw ApkgImporter.ApkgError.invalidZipArchive }
        let tailStart = max(0, data.count - 65_557)
        var end: Int?
        for offset in stride(from: data.count - 22, through: tailStart, by: -1) {
            if try uint32(data, offset) == 0x06054b50,
               offset + 22 + Int(try uint16(data, offset + 20)) == data.count {
                end = offset
                break
            }
        }
        guard let end,
              try uint16(data, end + 4) == 0, try uint16(data, end + 6) == 0 else {
            throw ApkgImporter.ApkgError.invalidZipArchive
        }
        let entries = Int(try uint16(data, end + 10))
        let centralSize = Int(try uint32(data, end + 12))
        var offset = Int(try uint32(data, end + 16))
        guard entries < 65_535, offset <= end, centralSize <= end - offset else {
            throw ApkgImporter.ApkgError.unsupportedCollection("This ZIP64 or split Anki archive is not supported.")
        }
        let centralEnd = offset + centralSize
        var names: Set<String> = []
        var totalSize = 0
        for _ in 0..<entries {
            guard offset + 46 <= centralEnd, try uint32(data, offset) == 0x02014b50 else {
                throw ApkgImporter.ApkgError.invalidZipArchive
            }
            let flags = try uint16(data, offset + 8)
            let method = try uint16(data, offset + 10)
            let checksum = try uint32(data, offset + 16)
            let compressedSize = Int(try uint32(data, offset + 20))
            let size = Int(try uint32(data, offset + 24))
            let nameLength = Int(try uint16(data, offset + 28))
            let extraLength = Int(try uint16(data, offset + 30))
            let commentLength = Int(try uint16(data, offset + 32))
            let attributes = try uint32(data, offset + 38)
            let localOffset = Int(try uint32(data, offset + 42))
            let next = offset + 46 + nameLength + extraLength + commentLength
            guard flags & 1 == 0, next <= centralEnd, size <= 512 * 1024 * 1024 else {
                throw ApkgImporter.ApkgError.invalidZipArchive
            }
            totalSize += size
            guard totalSize <= 2 * 1024 * 1024 * 1024 else {
                throw ApkgImporter.ApkgError.unsupportedCollection("The extracted Anki package exceeds the import size limit.")
            }
            guard let rawName = String(data: data.subdata(in: (offset + 46)..<(offset + 46 + nameLength)), encoding: .utf8),
                  !rawName.isEmpty else { throw ApkgImporter.ApkgError.invalidZipArchive }
            let isDirectory = rawName.hasSuffix("/")
            let name = isDirectory ? String(rawName.dropLast()) : rawName
            _ = try MediaManager.validatedRelativePath(name)
            guard names.insert(name).inserted, (attributes >> 16) & 0xf000 != 0xa000 else {
                throw ApkgImporter.ApkgError.invalidZipArchive
            }
            let destination = try MediaManager.mediaURL(for: name, in: directory)
            if isDirectory {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                offset = next
                continue
            }
            guard localOffset + 30 <= data.count, try uint32(data, localOffset) == 0x04034b50 else {
                throw ApkgImporter.ApkgError.invalidZipArchive
            }
            let payloadStart = localOffset + 30 + Int(try uint16(data, localOffset + 26)) + Int(try uint16(data, localOffset + 28))
            guard payloadStart <= data.count, compressedSize <= data.count - payloadStart else {
                throw ApkgImporter.ApkgError.invalidZipArchive
            }
            let compressed = data.subdata(in: payloadStart..<(payloadStart + compressedSize))
            let unpacked: Data
            switch method {
            case 0: unpacked = compressed
            case 8: unpacked = try inflateData(compressed, expectedSize: size)
            default:
                throw ApkgImporter.ApkgError.unsupportedCollection("Unsupported ZIP compression method \(method).")
            }
            let crc = unpacked.withUnsafeBytes { bytes in
                crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress, uInt(unpacked.count))
            }
            guard unpacked.count == size, UInt32(crc) == checksum else { throw ApkgImporter.ApkgError.invalidZipArchive }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try unpacked.write(to: destination, options: .atomic)
            offset = next
        }
        guard offset == centralEnd else { throw ApkgImporter.ApkgError.invalidZipArchive }
    }

    private static func inflateData(_ data: Data, expectedSize: Int) throws -> Data {
        var output = Data(count: max(expectedSize, 1))
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ApkgImporter.ApkgError.invalidZipArchive
        }
        defer { inflateEnd(&stream) }
        let result = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(expectedSize, 1))
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, Int(stream.total_out) == expectedSize else {
            throw ApkgImporter.ApkgError.invalidZipArchive
        }
        output.count = expectedSize
        return output
    }

    private static func uint16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw ApkgImporter.ApkgError.invalidZipArchive }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw ApkgImporter.ApkgError.invalidZipArchive }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}
