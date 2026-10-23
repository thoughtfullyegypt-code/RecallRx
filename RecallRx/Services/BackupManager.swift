import Foundation
import SwiftData

/// Backup Snapshot Information
struct BackupSnapshotInfo: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let filename: String
    let creationDate: Date
    let fileSize: Int64
    let formattedSize: String
    let reason: String
}

/// Automated Backup & Snapshot Engine for RecallRx
/// Automatically captures rolling periodic snapshots of the user's flashcards,
/// scheduling history, and decks to prevent data loss before exams.
final class BackupManager: ObservableObject {
    static let didRestoreNotification = Notification.Name("RecallRxDidRestoreBackup")
    static let shared: BackupManager = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return BackupManager(
            backupsDirectoryURL: appSupport.appendingPathComponent("RecallRx/Backups", isDirectory: true),
            mediaDirectoryURL: MediaManager.shared.directoryURL
        )
    }()

    @Published private(set) var lastError: String?
    private let backupsDirectoryURL: URL
    private let mediaDirectoryURL: URL
    private let saveContext: (ModelContext) throws -> Void
    private let maxRollingSnapshots: Int = 7

    /// Explicit directories keep tests and previews away from the user's real snapshots and media.
    init(
        backupsDirectoryURL: URL,
        mediaDirectoryURL: URL,
        saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.backupsDirectoryURL = backupsDirectoryURL
        self.mediaDirectoryURL = mediaDirectoryURL
        self.saveContext = saveContext
    }

    // MARK: - Snapshot Creation
    
    /// Creates a complete snapshot of all decks, cards, and review logs
    @discardableResult
    func createSnapshot(context: ModelContext, reason: String = "Manual") throws -> URL {
        let exportData = try BackupArchive.capture(context: context, mediaDirectoryURL: mediaDirectoryURL).encoded()
        try FileManager.default.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let safeReason = reason.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let filename = "RecallRx_Snapshot_\(timestamp)_\(safeReason)_\(UUID().uuidString).json"
        
        let fileURL = backupsDirectoryURL.appendingPathComponent(filename)
        try exportData.write(to: fileURL, options: .atomic)
        
        // Enforce rolling history limit
        pruneOldSnapshots(keeping: fileURL)
        
        lastError = nil
        return fileURL
    }
    
    /// Automatically captures a snapshot if the last snapshot was taken more than 12 hours ago
    func performAutoDailyBackupIfNeeded(context: ModelContext) {
        let snapshots = listSnapshots()
        if let newest = snapshots.first {
            let hoursSinceLast = Date().timeIntervalSince(newest.creationDate) / 3600.0
            if hoursSinceLast < 12.0 {
                return // Recently backed up
            }
        }
        
        do {
            try createSnapshot(context: context, reason: "AutoDaily")
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    // MARK: - Snapshot Management
    
    /// Lists all available snapshots sorted from newest to oldest
    func listSnapshots() -> [BackupSnapshotInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]) else {
            return []
        }
        
        var results: [BackupSnapshotInfo] = []
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.countStyle = .file
        
        for file in files where file.pathExtension.lowercased() == "json" {
            let filename = file.lastPathComponent
            let attrs = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let creationDate = attrs?.creationDate ?? Date()
            let fileSize = Int64(attrs?.fileSize ?? 0)
            
            var reason = "Auto"
            if filename.contains("Manual") {
                reason = "Manual"
            } else if filename.contains("AutoDaily") {
                reason = "Daily Auto"
            } else if filename.contains("PreRestore") {
                reason = "Pre-Restore Safety"
            }
            
            results.append(BackupSnapshotInfo(
                url: file,
                filename: filename,
                creationDate: creationDate,
                fileSize: fileSize,
                formattedSize: byteCountFormatter.string(fromByteCount: fileSize),
                reason: reason
            ))
        }
        
        return results.sorted(by: { $0.creationDate > $1.creationDate })
    }
    
    /// Restores database state from a chosen snapshot file
    func restoreSnapshot(from snapshotURL: URL, context: ModelContext) throws {
        // Decode and validate before any live models or files are changed.
        let archive = try BackupArchive.decode(Data(contentsOf: snapshotURL))
        // Preserve edits that were pending when Restore was requested, then require a safety copy.
        try context.save()
        try createSnapshot(context: context, reason: "PreRestore")
        let media = try archive.media.map {
            try BackupMediaStaging(records: $0, liveDirectory: mediaDirectoryURL)
        }
        let autosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosaveEnabled }

        do {
            try BackupStoreWriter.removeAllModels(context: context)
            try BackupStoreWriter.insert(archive, context: context, checkingExistingIDs: false)
            try media?.install()
            // This is the only save of the replacement, so failed writes can roll back the whole change.
            try saveContext(context)
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
        media?.finish()
        lastError = nil
        NotificationCenter.default.post(
            name: Self.didRestoreNotification,
            object: context,
            userInfo: [
                "deckIDs": archive.decks.map(\.id),
                "cardIDs": archive.cards.map(\.id),
                "reviewLogIDs": archive.reviewLogs.map(\.id)
            ]
        )
    }

    /// Deletes a specific snapshot file
    func deleteSnapshot(at fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    /// Keeps only the most recent N snapshots to save storage
    private func pruneOldSnapshots(keeping newestURL: URL) {
        let snapshots = listSnapshots()
        if snapshots.count > maxRollingSnapshots {
            // Filesystem creation times can tie; never prune the snapshot just written.
            let otherSnapshots = snapshots.filter { $0.url != newestURL }
            let toRemove = otherSnapshots.dropFirst(maxRollingSnapshots - 1)
            for snap in toRemove {
                try? FileManager.default.removeItem(at: snap.url)
            }
        }
    }
}
