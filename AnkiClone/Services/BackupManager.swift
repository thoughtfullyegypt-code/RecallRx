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
    static let shared = BackupManager()
    
    // Directory: Library/Application Support/RecallRx/Backups/
    private let backupsDirectoryURL: URL
    private let maxRollingSnapshots: Int = 7
    
    private init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recallRxURL = appSupportURL.appendingPathComponent("RecallRx", isDirectory: true)
        self.backupsDirectoryURL = recallRxURL.appendingPathComponent("Backups", isDirectory: true)
        
        try? fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    // MARK: - Snapshot Creation
    
    /// Creates a complete snapshot of all decks, cards, and review logs
    @discardableResult
    func createSnapshot(context: ModelContext, reason: String = "Manual") throws -> URL {
        let exportData = try ImportExportManager.exportAllDecks(context: context)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "RecallRx_Snapshot_\(timestamp)_\(reason).json"
        
        let fileURL = backupsDirectoryURL.appendingPathComponent(filename)
        try exportData.write(to: fileURL, options: .atomic)
        
        // Enforce rolling history limit
        pruneOldSnapshots()
        
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
        
        try? createSnapshot(context: context, reason: "AutoDaily")
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
        // 1. Create a safety backup of current state before restoring
        try? createSnapshot(context: context, reason: "PreRestore")
        
        // 2. Read snapshot data
        let data = try Data(contentsOf: snapshotURL)
        
        // 3. Clear existing decks, cards, and review logs
        let existingDecks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in existingDecks {
            context.delete(deck)
        }
        let existingCards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in existingCards {
            context.delete(card)
        }
        let existingLogs = (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []
        for log in existingLogs {
            context.delete(log)
        }
        try context.save()
        
        // 4. Import snapshot contents
        _ = try ImportExportManager.importAllDecks(from: data, context: context)
        try context.save()
    }
    
    /// Deletes a specific snapshot file
    func deleteSnapshot(at fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
    
    /// Keeps only the most recent N snapshots to save storage
    private func pruneOldSnapshots() {
        let snapshots = listSnapshots()
        if snapshots.count > maxRollingSnapshots {
            let toRemove = snapshots.dropFirst(maxRollingSnapshots)
            for snap in toRemove {
                try? FileManager.default.removeItem(at: snap.url)
            }
        }
    }
}
