import Foundation

/// Device-local durable inventory and deletion outbox, separate from user study data.
struct SyncJournal: Codable {
    var knownRecords: [String: String] = [:]
    var tombstones: [String: String] = [:]
    var pendingDeletions: [String: String] = [:]
    var restoredRecords: Set<String> = []
}
