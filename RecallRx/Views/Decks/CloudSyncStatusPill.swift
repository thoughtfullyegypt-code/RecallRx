import SwiftUI
import SwiftData

struct CloudSyncStatusPill: View {
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                statusLabel
                Spacer(minLength: 8)
                syncAction
            }
            VStack(alignment: .leading, spacing: 10) {
                statusLabel
                syncAction
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: .rect(cornerRadius: 14))
    }

    private var statusLabel: some View {
        Label(syncManager.syncStatus.displayText, systemImage: statusSymbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var syncAction: some View {
        if case .syncing = syncManager.syncStatus {
            ProgressView("Syncing")
                .labelsHidden()
                .accessibilityLabel("Syncing with iCloud")
                .frame(minWidth: 44, minHeight: 44)
        } else {
            Button(action: sync) {
                Label(isError ? "Retry" : "Sync", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isError ? "Retry iCloud sync" : "Sync with iCloud now")
        }
    }

    private var isError: Bool {
        if case .error = syncManager.syncStatus { return true }
        return false
    }

    private var statusSymbol: String {
        switch syncManager.syncStatus {
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }

    private func sync() {
        Task { await syncManager.triggerSync(context: modelContext) }
    }
}
