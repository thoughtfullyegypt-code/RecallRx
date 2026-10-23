import Foundation
import CryptoKit

/// Media is prepared before model mutations; existing assets are never overwritten on name collisions.
final class AnkiMediaImportTransaction {
    private let directory: URL
    private let staging: URL
    private var pendingNames: [String] = []
    private var installed: [URL] = []
    private(set) var names: [String: String] = [:]
    private(set) var count = 0

    init(extractedDirectory: URL, destination: URL, modern: Bool) throws {
        directory = destination
        staging = FileManager.default.temporaryDirectory.appendingPathComponent("anki_media_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let mapURL = extractedDirectory.appendingPathComponent("media")
            guard FileManager.default.fileExists(atPath: mapURL.path) else { return }
            let raw = try Data(contentsOf: mapURL)
            let map: [(String, String)]
            if modern {
                let decoded = try ApkgImporter.decompressZstdIfNeeded(raw)
                let message = try AnkiProtobuf(decoded)
                map = try (message.fields[1] ?? []).enumerated().map { index, entry in
                    let value = try AnkiProtobuf(entry)
                    guard let name = value.string(1) else { throw ApkgImporter.ApkgError.invalidMetadata }
                    return (String(value.integers[255]?.first ?? UInt64(index)), name)
                }
            } else {
                guard let json = try JSONSerialization.jsonObject(with: raw) as? [String: String] else {
                    throw ApkgImporter.ApkgError.invalidMetadata
                }
                map = json.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            }
            for (internalName, original) in map {
                guard names[original] == nil else { throw ApkgImporter.ApkgError.invalidMetadata }
                let source = try MediaManager.mediaURL(for: internalName, in: extractedDirectory)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw ApkgImporter.ApkgError.unsupportedCollection("The package is missing media file \(internalName) (\(original)).")
                }
                let data = try ApkgImporter.decompressZstdIfNeeded(Data(contentsOf: source))
                let originalURL = try MediaManager.mediaURL(for: original, in: directory)
                var resolved = original
                if FileManager.default.fileExists(atPath: originalURL.path), try Data(contentsOf: originalURL) != data {
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    let originalPath = original as NSString
                    let ext = originalPath.pathExtension
                    resolved = originalPath.deletingPathExtension + "_anki_" + digest + (ext.isEmpty ? "" : "." + ext)
                }
                let destinationURL = try MediaManager.mediaURL(for: resolved, in: directory)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    guard try Data(contentsOf: destinationURL) == data else { throw ApkgImporter.ApkgError.invalidMetadata }
                } else {
                    let prepared = try MediaManager.mediaURL(for: resolved, in: staging)
                    try FileManager.default.createDirectory(at: prepared.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: prepared, options: .atomic)
                    pendingNames.append(resolved)
                }
                names[original] = resolved
                count += 1
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: staging) }

    func install() throws {
        do {
            for name in pendingNames {
                let destination = try MediaManager.mediaURL(for: name, in: directory)
                let source = try MediaManager.mediaURL(for: name, in: staging)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                // copyItem refuses an unexpected existing destination rather than replacing it.
                try FileManager.default.copyItem(at: source, to: destination)
                installed.append(destination)
            }
        } catch {
            rollback()
            throw error
        }
    }

    func rollback() {
        for url in installed { try? FileManager.default.removeItem(at: url) }
        installed.removeAll()
    }
}
