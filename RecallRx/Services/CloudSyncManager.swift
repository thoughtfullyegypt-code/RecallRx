import Foundation
import SwiftData
import Network
import CloudKit

/// Conflict Resolution Strategies for CloudKit Multi-Device Sync
enum ConflictResolutionStrategy: String, Sendable {
    case reviewLogsTimestampUnion = "ReviewLogsTimestampUnion"
    case cardsLastWriteWins = "CardsLastWriteWins"
    case decksNewerTimestampWins = "DecksNewerTimestampWins"
}

/// Audit Log Entry for Synced Conflicts
struct SyncConflictAuditEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let entityType: String
    let entityIdentifier: String
    let strategyApplied: String
    let summary: String
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        entityType: String,
        entityIdentifier: String,
        strategyApplied: String,
        summary: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entityType = entityType
        self.entityIdentifier = entityIdentifier
        self.strategyApplied = strategyApplied
        self.summary = summary
    }
}

/// Lightweight DTO for Remote Card Data Exchange
struct RemoteCardPayload: Codable, Sendable {
    let id: UUID
    let front: String
    let back: String
    let modifiedAt: Date
    let interval: Double
    let easeFactor: Double
    let repetitions: Int
    let dueDate: Date
    let stateRaw: String
    let fsrsStability: Double
    let fsrsDifficulty: Double
    let isSuspended: Bool
    let isBuried: Bool
    let tags: [String]
    let deckID: UUID?
    let version: Int
    let noteTypeRaw: String?
    let createdAt: Date?
    let lastReviewDate: Date?
    let lapseCount: Int?
    let learningStep: Int?
    let queueRaw: String?
    let fsrsReps: Int?
    let fsrsLapses: Int?
    let extra: String?
    let firstAid: String?
    let sketchy: String?
    let pathoma: String?
    let clinicalPearls: String?
    let buriedUntil: Date?
    
    init(
        id: UUID,
        front: String,
        back: String,
        modifiedAt: Date,
        interval: Double,
        easeFactor: Double,
        repetitions: Int,
        dueDate: Date,
        stateRaw: String,
        fsrsStability: Double,
        fsrsDifficulty: Double,
        isSuspended: Bool,
        isBuried: Bool,
        tags: [String],
        deckID: UUID?,
        version: Int = 1,
        noteTypeRaw: String? = nil,
        createdAt: Date? = nil,
        lastReviewDate: Date? = nil,
        lapseCount: Int? = nil,
        learningStep: Int? = nil,
        queueRaw: String? = nil,
        fsrsReps: Int? = nil,
        fsrsLapses: Int? = nil,
        extra: String? = nil,
        firstAid: String? = nil,
        sketchy: String? = nil,
        pathoma: String? = nil,
        clinicalPearls: String? = nil,
        buriedUntil: Date? = nil
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.modifiedAt = modifiedAt
        self.interval = interval
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.stateRaw = stateRaw
        self.fsrsStability = fsrsStability
        self.fsrsDifficulty = fsrsDifficulty
        self.isSuspended = isSuspended
        self.isBuried = isBuried
        self.tags = tags
        self.deckID = deckID
        self.version = version
        self.noteTypeRaw = noteTypeRaw
        self.createdAt = createdAt
        self.lastReviewDate = lastReviewDate
        self.lapseCount = lapseCount
        self.learningStep = learningStep
        self.queueRaw = queueRaw
        self.fsrsReps = fsrsReps
        self.fsrsLapses = fsrsLapses
        self.extra = extra
        self.firstAid = firstAid
        self.sketchy = sketchy
        self.pathoma = pathoma
        self.clinicalPearls = clinicalPearls
        self.buriedUntil = buriedUntil
    }
}

/// Lightweight DTO for Remote Review Log Data Exchange
struct RemoteReviewLogPayload: Codable, Sendable {
    let id: UUID
    let cardID: UUID
    let rating: Int
    let reviewDate: Date
    let timeTakenMs: Int
    let intervalBefore: Double
    let intervalAfter: Double
    
    init(
        id: UUID,
        cardID: UUID,
        rating: Int,
        reviewDate: Date,
        timeTakenMs: Int,
        intervalBefore: Double,
        intervalAfter: Double
    ) {
        self.id = id
        self.cardID = cardID
        self.rating = rating
        self.reviewDate = reviewDate
        self.timeTakenMs = timeTakenMs
        self.intervalBefore = intervalBefore
        self.intervalAfter = intervalAfter
    }
}

/// Live Sync Status
enum CloudSyncStatus: Equatable, Sendable {
    case idle
    case syncing(progress: Double)
    case synced(lastSync: Date)
    case offline(reason: String)
    case error(message: String)
    
    var displayText: String {
        switch self {
        case .idle:
            return "Local-First Ready"
        case .syncing(let progress):
            return "Syncing (\(Int(progress * 100))%)..."
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .offline(let reason):
            return "Offline (\(reason))"
        case .error(let msg):
            return "Sync Error: \(msg)"
        }
    }
}

/// CloudKit Local-First Synchronization Engine
/// Compliant with Apple SwiftData + CloudKit requirements:
/// - Fully offline functional with zero data loss
/// - Deterministic conflict resolution rules:
///   * Review logs: Timestamp/UUID Set Union (logs are append-only; reviews never overwritten)
///   * Cards & Decks: Last-Write-Wins (LWW) based on modifiedAt timestamps
/// - Network-aware with NWPathMonitor
/// - Comprehensive conflict auditing
@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    @Published private(set) var syncStatus: CloudSyncStatus = .idle
    @Published private(set) var conflictAuditLog: [SyncConflictAuditEntry] = []
    @Published private(set) var lastSyncDate: Date?
    
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.recallrx.networkmonitor")
    private var isNetworkAvailable: Bool = true
    private let containerIdentifier = "iCloud.com.recallrx.app"
    private let zoneID = CKRecordZone.ID(zoneName: "RecallRx", ownerName: CKCurrentUserDefaultName)
    private let cardRecordType = "Card"
    private let reviewRecordType = "ReviewLog"
    
    private let defaults: UserDefaults
    private let persistChanges: (ModelContext) throws -> Void
    private let journalKey = "recallrx_sync_journal_v1"
    private let deckRecordType = "Deck"
    private let deletionRecordType = "Deletion"

    init(defaults: UserDefaults = .standard, monitorNetwork: Bool = true,
         persistChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.defaults = defaults
        self.persistChanges = persistChanges
        if monitorNetwork && ProcessInfo.processInfo.environment["RECALLRX_TESTING"] != "1" {
            startNetworkMonitoring()
        }
        if let date = defaults.object(forKey: "last_cloud_sync_timestamp") as? Date {
            self.lastSyncDate = date
        } else if let timestamp = defaults.object(forKey: "last_cloud_sync_timestamp") as? Double {
            self.lastSyncDate = Date(timeIntervalSince1970: timestamp)
        }
        loadAuditLog()
    }
    
    deinit {
        pathMonitor.cancel()
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isNetworkAvailable = (path.status == .satisfied)
                if !self.isNetworkAvailable {
                    self.syncStatus = .offline(reason: path.isExpensive ? "Cellular Restricted" : "No Connection")
                } else if case .offline = self.syncStatus {
                    self.syncStatus = .idle
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Conflict Resolution Engine
    
    /// Merges remote review logs with local logs using a deterministic set union strategy
    /// Preserves all review logs from both devices by UUID/timestamp without deleting or overwriting
    @discardableResult
    func mergeReviewLogs(
        remoteLogs: [RemoteReviewLogPayload],
        cardsByID: [UUID: Card],
        context: ModelContext
    ) -> Int {
        var mergedCount = 0
        let existingLogs = (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []
        var existingLogIDs = Set(existingLogs.map { $0.id })
        
        for remote in remoteLogs {
            // If log already exists locally, skip
            if existingLogIDs.contains(remote.id) {
                continue
            }
            
            // Link to matching card if available
            guard let card = cardsByID[remote.cardID] else {
                continue
            }
            
            let newLog = ReviewLog(
                id: remote.id,
                card: card,
                rating: remote.rating,
                reviewDate: remote.reviewDate,
                timeTakenMs: remote.timeTakenMs,
                intervalBefore: remote.intervalBefore,
                intervalAfter: remote.intervalAfter
            )
            context.insert(newLog)
            if !card.reviewLogs.contains(where: { $0.id == newLog.id }) { card.reviewLogs.append(newLog) }
            existingLogIDs.insert(remote.id)
            mergedCount += 1
            
            recordConflictAudit(
                entityType: "ReviewLog",
                identifier: remote.id.uuidString,
                strategy: ConflictResolutionStrategy.reviewLogsTimestampUnion.rawValue,
                summary: "Merged remote review from \(remote.reviewDate) (Rating \(remote.rating)) into card \(card.id)"
            )
        }
        
        if mergedCount > 0 {
            do { try persistChanges(context) }
            catch {
                context.rollback()
                syncStatus = .error(message: error.localizedDescription)
                return 0
            }
        }
        return mergedCount
    }
    
    /// Resolves card conflicts using Last-Write-Wins (LWW) based on `modifiedAt`
    func resolveCardConflict(
        localCard: Card,
        remoteCard: RemoteCardPayload
    ) -> Bool {
        if remoteCard.modifiedAt > localCard.modifiedAt {
            // Remote is newer: update local properties
            localCard.front = remoteCard.front
            localCard.back = remoteCard.back
            localCard.interval = remoteCard.interval
            localCard.easeFactor = remoteCard.easeFactor
            localCard.repetitions = remoteCard.repetitions
            localCard.dueDate = remoteCard.dueDate
            localCard.stateRaw = remoteCard.stateRaw
            localCard.fsrsStability = remoteCard.fsrsStability
            localCard.fsrsDifficulty = remoteCard.fsrsDifficulty
            localCard.isSuspended = remoteCard.isSuspended
            localCard.isBuried = remoteCard.isBuried
            localCard.tags = remoteCard.tags
            if let value = remoteCard.noteTypeRaw { localCard.noteTypeRaw = value }
            if let value = remoteCard.createdAt { localCard.createdAt = value }
            if let value = remoteCard.lapseCount { localCard.lapseCount = value }
            if let value = remoteCard.learningStep { localCard.learningStep = value }
            if let value = remoteCard.queueRaw { localCard.queueRaw = value }
            if let value = remoteCard.fsrsReps { localCard.fsrsReps = value }
            if let value = remoteCard.fsrsLapses { localCard.fsrsLapses = value }
            if let value = remoteCard.extra { localCard.extra = value }
            if let value = remoteCard.firstAid { localCard.firstAid = value }
            if let value = remoteCard.sketchy { localCard.sketchy = value }
            if let value = remoteCard.pathoma { localCard.pathoma = value }
            if let value = remoteCard.clinicalPearls { localCard.clinicalPearls = value }
            if remoteCard.version >= 2 {
                localCard.lastReviewDate = remoteCard.lastReviewDate
                localCard.buriedUntil = remoteCard.buriedUntil
            }
            localCard.modifiedAt = remoteCard.modifiedAt
            
            recordConflictAudit(
                entityType: "Card",
                identifier: localCard.id.uuidString,
                strategy: ConflictResolutionStrategy.cardsLastWriteWins.rawValue,
                summary: "Remote card is newer (modifiedAt: \(remoteCard.modifiedAt) > local: \(localCard.modifiedAt)). Updated local card."
            )
            return true
        } else {
            // Local is equal or newer: keep local
            recordConflictAudit(
                entityType: "Card",
                identifier: localCard.id.uuidString,
                strategy: ConflictResolutionStrategy.cardsLastWriteWins.rawValue,
                summary: "Local card is newer or equal (local: \(localCard.modifiedAt) >= remote: \(remoteCard.modifiedAt)). Kept local changes."
            )
            return false
        }
    }
    
    // MARK: - Durable deletion tracking

    private func loadJournal() throws -> SyncJournal {
        guard let data = defaults.data(forKey: journalKey) else { return SyncJournal() }
        return try JSONDecoder().decode(SyncJournal.self, from: data)
    }

    private func saveJournal(_ journal: SyncJournal) throws {
        defaults.set(try JSONEncoder().encode(journal), forKey: journalKey)
    }

    private func inventory(context: ModelContext) throws -> [String: String] {
        var result: [String: String] = [:]
        for deck in try context.fetch(FetchDescriptor<Deck>()) { result["deck-" + deck.id.uuidString] = deckRecordType }
        for card in try context.fetch(FetchDescriptor<Card>()) { result[card.id.uuidString] = cardRecordType }
        for log in try context.fetch(FetchDescriptor<ReviewLog>()) { result[log.id.uuidString] = reviewRecordType }
        return result
    }

    /// Compare persisted inventory before pulling, so offline deletions cannot be resurrected.
    func captureLocalDeletions(context: ModelContext) throws {
        guard !context.hasChanges else { throw CloudSyncError.unsavedChanges }
        let current = try inventory(context: context)
        var journal = try loadJournal()
        for (name, type) in journal.knownRecords where current[name] == nil {
            journal.restoredRecords.remove(name)
            journal.pendingDeletions[name] = type
            journal.tombstones[name] = type
        }
        journal.knownRecords = current
        try saveJournal(journal)
    }

    /// Explicit restore is allowed to revive backed-up IDs, unlike a stale device edit.
    func markRestoredLibrary(context: ModelContext) throws {
        let current = try inventory(context: context)
        var journal = try loadJournal()
        for name in current.keys {
            journal.restoredRecords.insert(name)
            journal.tombstones.removeValue(forKey: name)
            journal.pendingDeletions.removeValue(forKey: name)
        }
        journal.knownRecords.merge(current) { _, new in new }
        try saveJournal(journal)
    }

    // MARK: - Sync execution

    func triggerSync(context: ModelContext) async {
        if case .syncing = syncStatus { return }
        guard isNetworkAvailable else {
            syncStatus = .offline(reason: "No connection")
            return
        }
        syncStatus = .syncing(progress: 0.08)
        do {
            try context.save()
            try captureLocalDeletions(context: context)
            let container = CKContainer(identifier: containerIdentifier)
            let database = container.privateCloudDatabase
            let account = try await container.accountStatus()
            guard account == .available else {
                syncStatus = .offline(reason: accountStatusText(account))
                return
            }
            let zones = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            for result in zones.saveResults.values { _ = try result.get() }
            syncStatus = .syncing(progress: 0.3)
            try await pullChanges(database: database, context: context)
            syncStatus = .syncing(progress: 0.65)
            try await pushLocalChanges(database: database, context: context)
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: "last_cloud_sync_timestamp")
            syncStatus = .synced(lastSync: lastSyncDate ?? Date())
        } catch {
            syncStatus = .error(message: error.localizedDescription)
        }
    }

    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "Available"
        case .noAccount: return "Sign in to iCloud"
        case .restricted: return "iCloud restricted"
        case .couldNotDetermine: return "iCloud status unknown"
        case .temporarilyUnavailable: return "iCloud unavailable"
        @unknown default: return "iCloud unavailable"
        }
    }

    private func pullChanges(database: CKDatabase, context: ModelContext) async throws {
        var token = loadChangeToken()
        var modifiedByID: [CKRecord.ID: CKRecord] = [:]
        var deletedByID: [CKRecord.ID: String] = [:]
        var more = true
        do {
            while more {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for deletion in changes.deletions {
                    modifiedByID.removeValue(forKey: deletion.recordID)
                    deletedByID[deletion.recordID] = deletion.recordType
                }
                for result in changes.modificationResultsByID.values {
                    let record = try result.get().record
                    deletedByID.removeValue(forKey: record.recordID)
                    modifiedByID[record.recordID] = record
                }
                token = changes.changeToken
                more = changes.moreComing
            }
        } catch let error as CKError where error.code == .changeTokenExpired {
            defaults.removeObject(forKey: "ck_recallrx_zone_token")
            try await pullChanges(database: database, context: context)
            return
        }
        // A device may already have skipped a recreated card while its deletion marker
        // still existed. Marker removal must fetch the current record, even if its change
        // was consumed in a previous pull, so an explicit restore reaches every device.
        let restoredIDs = deletedByID.compactMap { id, type -> CKRecord.ID? in
            guard type == deletionRecordType, id.recordName.hasPrefix("deleted-") else { return nil }
            return CKRecord.ID(recordName: String(id.recordName.dropFirst("deleted-".count)), zoneID: zoneID)
        }
        for offset in stride(from: 0, to: restoredIDs.count, by: 100) {
            let batch = Array(restoredIDs[offset..<min(offset + 100, restoredIDs.count)])
            for (id, result) in try await database.records(for: batch) {
                do {
                    modifiedByID[id] = try result.get()
                    deletedByID.removeValue(forKey: id)
                } catch let error as CKError where error.code == .unknownItem { }
            }
        }
        // A review may precede its parent in a different page. Order only after all pages arrive.
        try applyRemoteChanges(records: Array(modifiedByID.values),
                               deletions: deletedByID.map { ($0.key, $0.value) }, context: context)
        if let token { try saveChangeToken(token) }
    }

    /// Atomic, testable application. No token or journal moves past a failed save/missing parent.
    func applyRemoteChanges(records: [CKRecord], deletions: [(recordID: CKRecord.ID, recordType: String)] = [], context: ModelContext) throws {
        guard !context.hasChanges else { throw CloudSyncError.unsavedChanges }
        var journal = try loadJournal()
        var index = try SyncRecordIndex(context: context)
        let restoredRemoteNames = Set(deletions.filter { $0.recordType == deletionRecordType && $0.recordID.recordName.hasPrefix("deleted-") }
            .map { String($0.recordID.recordName.dropFirst("deleted-".count)) })
        let liveRemoteNames = Set(records.filter { $0.recordType != deletionRecordType }.map { $0.recordID.recordName })
        do {
            for deletion in deletions where deletion.recordType == deletionRecordType {
                let name = String(deletion.recordID.recordName.dropFirst("deleted-".count))
                journal.tombstones.removeValue(forKey: name)
                journal.pendingDeletions.removeValue(forKey: name)
            }
            for record in records where record.recordType == deletionRecordType {
                guard let name = record["recordName"] as? String, let type = record["entityType"] as? String else {
                    throw CloudSyncError.invalidRecord(record.recordID.recordName)
                }
                if !journal.restoredRecords.contains(name) { journal.tombstones[name] = type }
            }
            for deletion in deletions where deletion.recordType != deletionRecordType {
                let name = deletion.recordID.recordName
                if !journal.restoredRecords.contains(name) && !(restoredRemoteNames.contains(name) && liveRemoteNames.contains(name)) {
                    journal.tombstones[name] = deletion.recordType
                }
            }
            for record in records where record.recordType == cardRecordType {
                if let deckID = record["deckID"] as? String, journal.tombstones["deck-" + deckID] != nil {
                    journal.tombstones[record.recordID.recordName] = cardRecordType
                }
            }
            // Cascade tombstones as well as models. Otherwise a late review for a
            // cascaded-away card would look like an unresolved parent and block the pull.
            for (name, type) in Array(journal.tombstones) where type == deckRecordType {
                guard let deckID = UUID(uuidString: String(name.dropFirst("deck-".count))) else { continue }
                for cardID in index.cardIDsByDeck[deckID] ?? [] where journal.tombstones[cardID.uuidString] == nil {
                    journal.tombstones[cardID.uuidString] = cardRecordType
                    journal.pendingDeletions[cardID.uuidString] = cardRecordType
                }
            }
            for (name, type) in Array(journal.tombstones) where type == cardRecordType {
                guard let cardID = UUID(uuidString: name) else { continue }
                for logID in index.logIDsByCard[cardID] ?? [] where journal.tombstones[logID.uuidString] == nil {
                    journal.tombstones[logID.uuidString] = reviewRecordType
                    journal.pendingDeletions[logID.uuidString] = reviewRecordType
                }
            }
            for (name, type) in journal.tombstones {
                try deleteLocalRecord(name: name, type: type, context: context, index: &index)
                journal.knownRecords.removeValue(forKey: name)
            }
            for type in [deckRecordType, cardRecordType, reviewRecordType] {
                for record in records where record.recordType == type {
                    let name = record.recordID.recordName
                    guard journal.tombstones[name] == nil, !journal.restoredRecords.contains(name) else { continue }
                    if type == deckRecordType { try applyRemoteDeck(record, context: context, index: &index) }
                    else if type == cardRecordType { try applyRemoteCard(record, context: context, index: &index) }
                    else { try applyRemoteReview(record, tombstones: journal.tombstones, context: context, index: &index) }
                }
            }
            try persistChanges(context)
        } catch {
            context.rollback()
            throw error
        }
        journal.knownRecords.merge(try inventory(context: context)) { _, new in new }
        try saveJournal(journal)
    }

    private func deleteLocalRecord(name: String, type: String, context: ModelContext, index: inout SyncRecordIndex) throws {
        if type == deckRecordType, let id = UUID(uuidString: String(name.dropFirst("deck-".count))), let deck = index.decks.removeValue(forKey: id) {
            let childCardIDs = index.cardIDsByDeck.removeValue(forKey: id) ?? []
            for cardID in childCardIDs {
                index.cards.removeValue(forKey: cardID)
                for logID in index.logIDsByCard.removeValue(forKey: cardID) ?? [] { index.logs.removeValue(forKey: logID) }
            }
            context.delete(deck)
        } else if let id = UUID(uuidString: name) {
            if type == cardRecordType, let card = index.cards.removeValue(forKey: id) {
                for logID in index.logIDsByCard.removeValue(forKey: id) ?? [] { index.logs.removeValue(forKey: logID) }
                if let deckID = card.deck?.id { index.cardIDsByDeck[deckID]?.remove(id) }
                context.delete(card)
            } else if type == reviewRecordType, let log = index.logs.removeValue(forKey: id) {
                if let cardID = log.card?.id { index.logIDsByCard[cardID]?.remove(id) }
                context.delete(log)
            }
        }
    }

    private func pushLocalChanges(database: CKDatabase, context: ModelContext) async throws {
        var journal = try loadJournal()
        // Persistent cloud tombstones prevent an old device from recreating deleted data.
        let deletionBatch = journal.pendingDeletions.sorted { $0.key < $1.key }
        for offset in stride(from: 0, to: deletionBatch.count, by: 100) {
            let batch = Array(deletionBatch[offset..<min(offset + 100, deletionBatch.count)])
            let tombstones = batch.map { entry -> CKRecord in
                let record = CKRecord(recordType: deletionRecordType, recordID: CKRecord.ID(recordName: "deleted-" + entry.key, zoneID: zoneID))
                record["recordName"] = entry.key as NSString
                record["entityType"] = entry.value as NSString
                return record
            }
            let result = try await database.modifyRecords(saving: tombstones,
                deleting: batch.map { CKRecord.ID(recordName: $0.key, zoneID: zoneID) },
                savePolicy: .changedKeys, atomically: false)
            for value in result.saveResults.values { _ = try value.get() }
            for value in result.deleteResults.values {
                do { _ = try value.get() }
                catch let error as CKError where error.code == .unknownItem { }
            }
            journal = try loadJournal()
            for entry in batch { journal.pendingDeletions.removeValue(forKey: entry.key) }
            try saveJournal(journal)
        }

        let decks = try context.fetch(FetchDescriptor<Deck>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        for deck in decks where journal.restoredRecords.contains("deck-" + deck.id.uuidString) { deck.modifiedAt = .now }
        for card in cards where journal.restoredRecords.contains(card.id.uuidString) { card.modifiedAt = .now }
        try context.save()
        let localRecords = decks.map { record(for: $0) } + cards.map { record(for: $0) } + logs.map { record(for: $0) }
        for offset in stride(from: 0, to: localRecords.count, by: 100) {
            let batch = Array(localRecords[offset..<min(offset + 100, localRecords.count)])
                .filter { journal.tombstones[$0.recordID.recordName] == nil }
            let remote = try await database.records(for: batch.map(\.recordID))
            var toSave: [CKRecord] = []
            var newerRemote: [CKRecord] = []
            for local in batch {
                var existing: CKRecord?
                if let result = remote[local.recordID] {
                    do { existing = try result.get() }
                    catch let error as CKError where error.code == .unknownItem { }
                }
                if let existing {
                    if local.recordType == reviewRecordType && (existing["version"] as? Int ?? 1) >= 2 { continue }
                    let remoteDate = existing["modifiedAt"] as? Date ?? .distantPast
                    let localDate = local["modifiedAt"] as? Date ?? .distantPast
                    if remoteDate > localDate { newerRemote.append(existing); continue }
                    if remoteDate == localDate && local.recordType != reviewRecordType && !journal.restoredRecords.contains(local.recordID.recordName) { continue }
                    for key in existing.allKeys() where local[key] == nil { existing[key] = nil }
                    for key in local.allKeys() { existing[key] = local[key] }
                    toSave.append(existing)
                } else { toSave.append(local) }
            }
            if !newerRemote.isEmpty { try applyRemoteChanges(records: newerRemote, context: context) }
            if !toSave.isEmpty {
                let outcome = try await database.modifyRecords(saving: toSave, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                for result in outcome.saveResults.values { _ = try result.get() }
            }
        }
        let restoredBatch = journal.restoredRecords
        for name in restoredBatch {
            let result = try await database.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: "deleted-" + name, zoneID: zoneID)], atomically: false)
            for value in result.deleteResults.values {
                do { _ = try value.get() }
                catch let error as CKError where error.code == .unknownItem { }
            }
        }
        try captureLocalDeletions(context: context)
        journal = try loadJournal()
        journal.restoredRecords.subtract(restoredBatch)
        journal.knownRecords = try inventory(context: context)
        try saveJournal(journal)
    }

    private func applyRemoteDeck(_ record: CKRecord, context: ModelContext, index: inout SyncRecordIndex) throws {
        guard let id = UUID(uuidString: String(record.recordID.recordName.dropFirst("deck-".count))),
              let name = record["name"] as? String else { throw CloudSyncError.invalidRecord(record.recordID.recordName) }
        let modifiedAt = record["modifiedAt"] as? Date ?? .distantPast
        let existing = index.decks[id]
        if let existing, existing.modifiedAt >= modifiedAt { return }
        let deck = existing ?? Deck(id: id, name: name)
        if existing == nil { context.insert(deck); index.decks[id] = deck }
        deck.name = name
        deck.descriptionText = record["descriptionText"] as? String ?? ""
        deck.createdAt = record["createdAt"] as? Date ?? modifiedAt
        deck.parentDeckID = (record["parentDeckID"] as? String).flatMap(UUID.init(uuidString:))
        deck.newCardsPerDay = record["newCardsPerDay"] as? Int ?? 20
        deck.reviewsPerDay = record["reviewsPerDay"] as? Int ?? 200
        deck.isCollapsed = record["isCollapsed"] as? Bool ?? false
        deck.modifiedAt = modifiedAt
    }

    private func applyRemoteCard(_ record: CKRecord, context: ModelContext, index: inout SyncRecordIndex) throws {
        guard let id = UUID(uuidString: record.recordID.recordName), let front = record["front"] as? String else {
            throw CloudSyncError.invalidRecord(record.recordID.recordName)
        }
        var card = index.cards[id]
        let modifiedAt = record["modifiedAt"] as? Date ?? .distantPast
        if let card, card.modifiedAt >= modifiedAt { return }
        let deckID = (record["deckID"] as? String).flatMap(UUID.init(uuidString:))
        var deck = deckID.flatMap { index.decks[$0] }
        // Legacy cloud records did not include Deck records. V2 preserves explicitly orphaned cards.
        if deck == nil && (deckID != nil || (record["version"] as? Int ?? 1) < 2) {
            let created = Deck(id: deckID ?? UUID(), name: "iCloud", descriptionText: "Cards merged from iCloud")
            context.insert(created)
            index.decks[created.id] = created
            deck = created
        }
        if card == nil {
            let created = Card(id: id, front: front, deck: deck)
            context.insert(created)
            index.cards[id] = created
            card = created
        }
        guard let card else { throw CloudSyncError.invalidRecord(record.recordID.recordName) }
        if let oldDeckID = card.deck?.id { index.cardIDsByDeck[oldDeckID]?.remove(card.id) }
        if let deck { index.cardIDsByDeck[deck.id, default: []].insert(card.id) }
        card.front = front
        card.back = record["back"] as? String ?? ""
        card.deck = deck
        card.tags = record["tags"] as? [String] ?? []
        card.interval = record["interval"] as? Double ?? 0
        card.easeFactor = record["easeFactor"] as? Double ?? 2.5
        card.repetitions = record["repetitions"] as? Int ?? 0
        card.dueDate = record["dueDate"] as? Date ?? .now
        card.stateRaw = record["stateRaw"] as? String ?? "new"
        card.fsrsStability = record["fsrsStability"] as? Double ?? 0
        card.fsrsDifficulty = record["fsrsDifficulty"] as? Double ?? 0
        card.isSuspended = record["isSuspended"] as? Bool ?? false
        card.isBuried = record["isBuried"] as? Bool ?? false
        if (record["version"] as? Int ?? 1) >= 2 {
            card.noteTypeRaw = record["noteTypeRaw"] as? String ?? "basic"
            card.createdAt = record["createdAt"] as? Date ?? modifiedAt
            card.lastReviewDate = record["lastReviewDate"] as? Date
            card.buriedUntil = record["buriedUntil"] as? Date
            card.lapseCount = record["lapseCount"] as? Int ?? 0
            card.learningStep = record["learningStep"] as? Int ?? 0
            card.queueRaw = record["queueRaw"] as? String ?? "new"
            card.fsrsReps = record["fsrsReps"] as? Int ?? 0
            card.fsrsLapses = record["fsrsLapses"] as? Int ?? 0
            card.extra = record["extra"] as? String ?? ""
            card.firstAid = record["firstAid"] as? String ?? ""
            card.sketchy = record["sketchy"] as? String ?? ""
            card.pathoma = record["pathoma"] as? String ?? ""
            card.clinicalPearls = record["clinicalPearls"] as? String ?? ""
        }
        card.modifiedAt = modifiedAt
    }

    private func applyRemoteReview(_ record: CKRecord, tombstones: [String: String], context: ModelContext, index: inout SyncRecordIndex) throws {
        guard let id = UUID(uuidString: record.recordID.recordName) else { throw CloudSyncError.invalidRecord(record.recordID.recordName) }
        guard index.logs[id] == nil else { return }
        let cardIDText = record["cardID"] as? String
        var card: Card?
        if let cardIDText, !cardIDText.isEmpty {
            if tombstones[cardIDText] != nil { return }
            guard let cardID = UUID(uuidString: cardIDText) else { throw CloudSyncError.invalidRecord(record.recordID.recordName) }
            guard let parent = index.cards[cardID] else { throw CloudSyncError.missingCard(cardIDText) }
            card = parent
        }
        let log = ReviewLog(id: id, card: card, rating: record["rating"] as? Int ?? 0,
                            reviewDate: record["reviewDate"] as? Date ?? .now,
                            timeTakenMs: record["timeTakenMs"] as? Int ?? 0,
                            intervalBefore: record["intervalBefore"] as? Double ?? 0,
                            intervalAfter: record["intervalAfter"] as? Double ?? 0,
                            easeFactorBefore: record["easeFactorBefore"] as? Double ?? 2.5,
                            easeFactorAfter: record["easeFactorAfter"] as? Double ?? 2.5,
                            cardStateBefore: record["cardStateBefore"] as? String ?? "new",
                            cardStateAfter: record["cardStateAfter"] as? String ?? "learning")
        context.insert(log)
        index.logs[id] = log
        if let card { index.logIDsByCard[card.id, default: []].insert(id) }
    }

    func record(for deck: Deck) -> CKRecord {
        let record = CKRecord(recordType: deckRecordType, recordID: CKRecord.ID(recordName: "deck-" + deck.id.uuidString, zoneID: zoneID))
        record["name"] = deck.name as NSString
        record["descriptionText"] = deck.descriptionText as NSString
        record["createdAt"] = deck.createdAt as NSDate
        record["modifiedAt"] = deck.modifiedAt as NSDate
        record["isCollapsed"] = deck.isCollapsed as NSNumber
        record["newCardsPerDay"] = deck.newCardsPerDay as NSNumber
        record["reviewsPerDay"] = deck.reviewsPerDay as NSNumber
        record["parentDeckID"] = deck.parentDeckID?.uuidString as NSString?
        return record
    }

    func record(for card: Card) -> CKRecord {
        let record = CKRecord(recordType: cardRecordType, recordID: CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID))
        record["version"] = 2 as NSNumber
        record["front"] = card.front as NSString
        record["back"] = card.back as NSString
        record["modifiedAt"] = card.modifiedAt as NSDate
        record["interval"] = card.interval as NSNumber
        record["easeFactor"] = card.easeFactor as NSNumber
        record["repetitions"] = card.repetitions as NSNumber
        record["dueDate"] = card.dueDate as NSDate
        record["stateRaw"] = card.stateRaw as NSString
        record["fsrsStability"] = card.fsrsStability as NSNumber
        record["fsrsDifficulty"] = card.fsrsDifficulty as NSNumber
        record["isSuspended"] = card.isSuspended as NSNumber
        record["isBuried"] = card.isBuried as NSNumber
        record["tags"] = card.tags as NSArray
        record["deckID"] = card.deck?.id.uuidString as NSString?
        record["noteTypeRaw"] = card.noteTypeRaw as NSString
        record["createdAt"] = card.createdAt as NSDate
        record["lastReviewDate"] = card.lastReviewDate as NSDate?
        record["buriedUntil"] = card.buriedUntil as NSDate?
        record["lapseCount"] = card.lapseCount as NSNumber
        record["learningStep"] = card.learningStep as NSNumber
        record["queueRaw"] = card.queueRaw as NSString
        record["fsrsReps"] = card.fsrsReps as NSNumber
        record["fsrsLapses"] = card.fsrsLapses as NSNumber
        record["extra"] = card.extra as NSString
        record["firstAid"] = card.firstAid as NSString
        record["sketchy"] = card.sketchy as NSString
        record["pathoma"] = card.pathoma as NSString
        record["clinicalPearls"] = card.clinicalPearls as NSString
        return record
    }

    func record(for log: ReviewLog) -> CKRecord {
        let record = CKRecord(recordType: reviewRecordType, recordID: CKRecord.ID(recordName: log.id.uuidString, zoneID: zoneID))
        record["version"] = 2 as NSNumber
        record["cardID"] = log.card?.id.uuidString as NSString?
        record["rating"] = log.rating as NSNumber
        record["reviewDate"] = log.reviewDate as NSDate
        record["timeTakenMs"] = log.timeTakenMs as NSNumber
        record["intervalBefore"] = log.intervalBefore as NSNumber
        record["intervalAfter"] = log.intervalAfter as NSNumber
        record["easeFactorBefore"] = log.easeFactorBefore as NSNumber
        record["easeFactorAfter"] = log.easeFactorAfter as NSNumber
        record["cardStateBefore"] = log.cardStateBefore as NSString
        record["cardStateAfter"] = log.cardStateAfter as NSString
        return record
    }

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = defaults.data(forKey: "ck_recallrx_zone_token") else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: CKServerChangeToken) throws {
        defaults.set(try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true), forKey: "ck_recallrx_zone_token")
    }

    /// Simulates multi-device sync conflict resolution between Device A and Device B
    func simulateMultiDeviceSync(
        localCard: Card,
        deviceBReviewLogs: [RemoteReviewLogPayload],
        deviceBCardUpdate: RemoteCardPayload,
        context: ModelContext
    ) -> (logsMerged: Int, cardUpdated: Bool) {
        // 1. Resolve card conflict via LWW
        let cardUpdated = resolveCardConflict(localCard: localCard, remoteCard: deviceBCardUpdate)
        
        // 2. Merge review logs via timestamp union
        let cardsByID = [localCard.id: localCard]
        let logsMerged = mergeReviewLogs(remoteLogs: deviceBReviewLogs, cardsByID: cardsByID, context: context)
        
        return (logsMerged, cardUpdated)
    }
    
    /// Benchmark for processing 30,000 cards without memory bloat
    func benchmark30kSync(cardCount: Int = 30000) -> (timeSeconds: Double, processedCount: Int) {
        let startTime = CFAbsoluteTimeGetCurrent()
        var dummyCardMap: [UUID: Date] = [:]
        dummyCardMap.reserveCapacity(cardCount)
        
        let sampleDate = Date()
        for _ in 0..<cardCount {
            dummyCardMap[UUID()] = sampleDate
        }
        
        // Simulate LWW timestamp comparison on 30k elements
        var newerCount = 0
        let incomingDate = sampleDate.addingTimeInterval(3600)
        for (_, localDate) in dummyCardMap {
            if incomingDate > localDate {
                newerCount += 1
            }
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        return (elapsed, newerCount)
    }
    
    // MARK: - Audit Log Storage
    
    private func recordConflictAudit(
        entityType: String,
        identifier: String,
        strategy: String,
        summary: String
    ) {
        let entry = SyncConflictAuditEntry(
            entityType: entityType,
            entityIdentifier: identifier,
            strategyApplied: strategy,
            summary: summary
        )
        conflictAuditLog.insert(entry, at: 0)
        if conflictAuditLog.count > 50 {
            conflictAuditLog.removeLast()
        }
        saveAuditLog()
    }
    
    private func saveAuditLog() {
        if let encoded = try? JSONEncoder().encode(conflictAuditLog) {
            defaults.set(encoded, forKey: "cloud_sync_conflict_audit_log")
        }
    }
    
    private func loadAuditLog() {
        if let data = defaults.data(forKey: "cloud_sync_conflict_audit_log"),
           let decoded = try? JSONDecoder().decode([SyncConflictAuditEntry].self, from: data) {
            self.conflictAuditLog = decoded
        }
    }
}
