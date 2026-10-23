import Foundation

/// Stages complete media directories beside the live directory so moves stay on one volume.
final class BackupMediaStaging {
    private let liveDirectory: URL
    private let stagedDirectory: URL
    private let fileManager = FileManager.default
    private(set) var recoveryDirectory: URL?
    private var installed = false

    init(records: [BackupMediaRecord], liveDirectory: URL, preserveExisting: Bool = false) throws {
        self.liveDirectory = liveDirectory
        let parent = liveDirectory.deletingLastPathComponent()
        stagedDirectory = parent.appendingPathComponent(".RecallRx-Media-Stage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagedDirectory, withIntermediateDirectories: false)
        do {
            var assets: [String: BackupMediaRecord] = [:]
            if preserveExisting {
                for asset in try Self.readMedia(in: liveDirectory) {
                    assets[asset.relativePath.lowercased()] = asset
                }
            }
            for asset in records {
                let path = try MediaManager.validatedRelativePath(asset.relativePath)
                if let existing = assets[path.lowercased()], existing.data != asset.data {
                    throw BackupArchiveError.invalid("an imported media filename conflicts with existing media: \(path)")
                }
                assets[path.lowercased()] = asset
            }
            for asset in assets.values {
                let destination = try MediaManager.mediaURL(for: asset.relativePath, in: stagedDirectory)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try asset.data.write(to: destination, options: .atomic)
            }
        } catch {
            try? fileManager.removeItem(at: stagedDirectory)
            throw error
        }
    }

    func install() throws {
        if fileManager.fileExists(atPath: liveDirectory.path) {
            let recovery = liveDirectory.deletingLastPathComponent()
                .appendingPathComponent(".RecallRx-Media-Recovery-\(UUID().uuidString)", isDirectory: true)
            try fileManager.moveItem(at: liveDirectory, to: recovery)
            recoveryDirectory = recovery
        }
        try fileManager.moveItem(at: stagedDirectory, to: liveDirectory)
        installed = true
    }

    func rollback() throws {
        if installed {
            try fileManager.removeItem(at: liveDirectory)
            installed = false
        }
        if let recoveryDirectory {
            try fileManager.moveItem(at: recoveryDirectory, to: liveDirectory)
            self.recoveryDirectory = nil
        }
    }

    func finish() {
        if let recoveryDirectory {
            try? fileManager.removeItem(at: recoveryDirectory)
            self.recoveryDirectory = nil
        }
    }

    deinit {
        // Never remove the recovery directory here: it may be the only surviving original media.
        try? fileManager.removeItem(at: stagedDirectory)
    }

    static func readMedia(in directory: URL) throws -> [BackupMediaRecord] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let root = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root.isDirectory == true, root.isSymbolicLink != true else {
            throw BackupArchiveError.invalid("the media directory is not a regular directory")
        }
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else { throw BackupArchiveError.invalid("media could not be read") }
        var media: [BackupMediaRecord] = []
        let prefix = directory.standardizedFileURL.path + "/"
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw BackupArchiveError.invalid("media contains a symbolic link")
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, url.standardizedFileURL.path.hasPrefix(prefix) else {
                throw BackupArchiveError.invalid("media contains an unsupported file")
            }
            let relativePath = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            _ = try MediaManager.validatedRelativePath(relativePath)
            media.append(BackupMediaRecord(relativePath: relativePath, data: try Data(contentsOf: url)))
        }
        if let enumerationError { throw enumerationError }
        return media.sorted { $0.relativePath < $1.relativePath }
    }
}
