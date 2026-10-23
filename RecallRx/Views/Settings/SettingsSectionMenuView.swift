import SwiftUI

struct SettingsSectionMenuView: View {
    let useFSRS: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make RecallRx yours")
                .font(.title2.bold())
            Text("Adjust your study routine, manage your library, and keep your progress safe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Menu {
                Section("Study & Appearance") {
                    Button("Appearance", systemImage: "paintpalette") { onSelect("appearance_settings") }
                    Button("Study Routine", systemImage: "book") { onSelect("study_settings") }
                    Button("Spaced Repetition", systemImage: "brain") { onSelect("review_settings") }
                    if useFSRS {
                        Button("FSRS Personalization", systemImage: "slider.horizontal.3") { onSelect("fsrs_personalization") }
                    }
                    Button("Burnout Shield", systemImage: "shield") { onSelect("burnout_shield") }
                    Button("Reminders", systemImage: "bell") { onSelect("reminder_settings") }
                }
                Section("Library & Devices") {
                    Button("Import & Export", systemImage: "square.and.arrow.up") { onSelect("data_management") }
                    Button("Backups", systemImage: "externaldrive") { onSelect("backup_settings") }
                    Button("iCloud Sync", systemImage: "icloud") { onSelect("cloud_sync_settings") }
                    Button("Remote Controls", systemImage: "gamecontroller") { onSelect("bluetooth_settings") }
                    Button("Hands-Free Settings", systemImage: "waveform") { onSelect("driving_settings") }
                    Button("Widgets", systemImage: "square.grid.2x2") { onSelect("widgets_settings") }
                }
                Section("About RecallRx") {
                    Button("Free Forever Guarantee", systemImage: "checkmark.seal") { onSelect("pricing_guarantee") }
                    Button("About & Source Code", systemImage: "info.circle") { onSelect("about_settings") }
                    Button("Reset & Delete", systemImage: "trash") { onSelect("destructive_settings") }
                }
            } label: {
                Label("Jump to a Section", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
    }
}
