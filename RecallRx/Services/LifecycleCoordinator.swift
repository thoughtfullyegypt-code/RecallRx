import Foundation
import SwiftData

/// Coalesces successful saves and foreground events into one refresh of derived data.
@MainActor
final class LifecycleCoordinator {
    static let shared = LifecycleCoordinator()

    private let isEnabled: Bool
    private let debounceNanoseconds: UInt64
    private let widgetRefresh: @MainActor (ModelContext) -> WidgetSnapshotData
    private let reminderRefresh: @MainActor (WidgetSnapshotData) async -> Void
    private let automaticBackup: @MainActor (ModelContext) -> Void
    private let captureLocalDeletions: @MainActor (ModelContext) throws -> Void
    private let markRestoredLibrary: @MainActor (ModelContext) throws -> Void
    private weak var observedContext: ModelContext?
    private var saveObserver: NSObjectProtocol?
    private var restoreObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private(set) var lastError: String?

    /// Actions are injected in regression tests, so no shared directories or system APIs are touched.
    init(
        isEnabled: Bool = !AppRuntime.isTesting,
        debounceNanoseconds: UInt64 = 500_000_000,
        widgetRefresh: (@MainActor (ModelContext) -> WidgetSnapshotData)? = nil,
        reminderRefresh: (@MainActor (WidgetSnapshotData) async -> Void)? = nil,
        automaticBackup: (@MainActor (ModelContext) -> Void)? = nil,
        captureLocalDeletions: (@MainActor (ModelContext) throws -> Void)? = nil,
        markRestoredLibrary: (@MainActor (ModelContext) throws -> Void)? = nil
    ) {
        self.isEnabled = isEnabled
        self.debounceNanoseconds = debounceNanoseconds
        // Resolve singletons lazily: a disabled test lifecycle must not create backup folders.
        self.widgetRefresh = widgetRefresh ?? { WidgetDataManager.shared.updateWidgetData(context: $0) }
        self.reminderRefresh = reminderRefresh ?? { snapshot in
            await NotificationManager.shared.refreshDailyReminder(dueCount: snapshot.totalDue, streakDays: snapshot.streakDays)
        }
        self.automaticBackup = automaticBackup ?? { BackupManager.shared.performAutoDailyBackupIfNeeded(context: $0) }
        self.captureLocalDeletions = captureLocalDeletions ?? { try CloudSyncManager.shared.captureLocalDeletions(context: $0) }
        self.markRestoredLibrary = markRestoredLibrary ?? { try CloudSyncManager.shared.markRestoredLibrary(context: $0) }
    }

    deinit {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        if let restoreObserver { NotificationCenter.default.removeObserver(restoreObserver) }
        refreshTask?.cancel()
    }

    func start(context: ModelContext) {
        guard isEnabled else { return }
        if observedContext !== context {
            if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
            observedContext = context
            saveObserver = NotificationCenter.default.addObserver(
                forName: ModelContext.didSave, object: nil, queue: .main
            ) { [weak self, weak context] notification in
                Task { @MainActor in
                    guard let self, let context,
                          self.observedContext === context else { return }
                    if let savedContext = notification.object as? ModelContext,
                       savedContext.container !== context.container { return }
                    self.requestRefresh(context: context)
                }
            }
            if let restoreObserver { NotificationCenter.default.removeObserver(restoreObserver) }
            restoreObserver = NotificationCenter.default.addObserver(
                forName: BackupManager.didRestoreNotification, object: nil, queue: .main
            ) { [weak self, weak context] notification in
                // Restore posts synchronously on the main actor. Mark restored UUIDs before
                // the save observer's asynchronous debounce can record replacement deletions.
                MainActor.assumeIsolated {
                    guard let self, let context,
                          let restoredContext = notification.object as? ModelContext,
                          restoredContext.container === context.container else { return }
                    do {
                        try self.markRestoredLibrary(restoredContext)
                        self.lastError = nil
                    } catch {
                        self.lastError = error.localizedDescription
                        print("[LifecycleCoordinator] Could not mark restored sync records: \(error.localizedDescription)")
                    }
                    self.requestRefresh(context: context)
                }
            }
        }
        requestRefresh(context: context)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        if let restoreObserver { NotificationCenter.default.removeObserver(restoreObserver) }
        saveObserver = nil
        restoreObserver = nil
        observedContext = nil
    }

    func requestRefresh(context: ModelContext) {
        guard isEnabled else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self, weak context] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.debounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let context else { return }
            await self.performRefresh(context: context)
        }
    }

    /// An explicit refresh is useful after a completed sync or a preference change.
    func refresh(context: ModelContext) async {
        guard isEnabled else { return }
        refreshTask?.cancel()
        await performRefresh(context: context)
    }

    private func performRefresh(context: ModelContext) async {
        // Fetch only committed state. A later successful didSave will retry pending edits.
        guard !context.hasChanges, !Task.isCancelled else { return }
        do {
            try captureLocalDeletions(context)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[LifecycleCoordinator] Could not capture sync changes: \(error.localizedDescription)")
        }
        let snapshot = widgetRefresh(context)
        automaticBackup(context)
        guard !Task.isCancelled else { return }
        await reminderRefresh(snapshot)
    }
}
