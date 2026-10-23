import SwiftUI

// MARK: - Cloud Sync Conflict Audit View

struct CloudSyncAuditView: View {
    @ObservedObject private var syncManager = CloudSyncManager.shared

    var body: some View {
        List {
            if syncManager.conflictAuditLog.isEmpty {
                ContentUnavailableView(
                    "No Recorded Conflicts",
                    systemImage: "checkmark.icloud",
                    description: Text("Conflicts resolved during sync will appear here.")
                )
            } else {
                ForEach(syncManager.conflictAuditLog) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.entityType)
                                .font(.footnote.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.12))
                                .foregroundStyle(AppTheme.accent)
                                .clipShape(Capsule())

                            Spacer()

                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Text(entry.summary)
                            .font(.subheadline)

                        Text("Strategy: \(entry.strategyApplied)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
        .navigationTitle("Conflict Audit Log")
    }
}
