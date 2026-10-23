import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - AppStorage Settings
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("appAccentColor") private var appAccentColor: String = "Teal"

    // Study Settings
    @AppStorage("showTimer") private var showTimer: Bool = true
    @AppStorage("autoAdvance") private var autoAdvance: Bool = false
    @AppStorage("defaultNewCardsPerDay") private var defaultNewCardsPerDay: Int = 20
    @AppStorage("defaultMaxReviewsPerDay") private var defaultMaxReviewsPerDay: Int = 200
    @AppStorage("userTargetExam") private var targetExam = "USMLE Step 1"

    // Review Settings
    @AppStorage("useFSRS") private var useFSRS: Bool = true
    @AppStorage("fsrsTargetRetention") private var fsrsTargetRetention: Double = 0.90
    @AppStorage("showNextReviewTime") private var showNextReviewTime: Bool = true
    @AppStorage("learningSteps") private var learningSteps: String = "1m 10m"
    @AppStorage("graduatingInterval") private var graduatingInterval: Int = 1
    @AppStorage("easyInterval") private var easyInterval: Int = 4

    // Medical Unfair Advantages & Remotes
    @ObservedObject private var drivingManager = DrivingModeManager.shared
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @AppStorage("enableLoadBalancer") private var enableLoadBalancer: Bool = true
    @AppStorage("burnoutShieldMaxDaily") private var burnoutShieldMaxDaily: Int = 150

    // MARK: - State Variables
    @State private var showResetConfirmation: Bool = false
    @State private var showDeleteAllDecksConfirmation: Bool = false
    @State private var showExportShareSheet: Bool = false
    @State private var exportedDataURL: URL?
    @State private var showFileImporter: Bool = false
    @State private var statusMessage: String?
    @State private var showStatusAlert: Bool = false
    @State private var isOptimizingFSRS: Bool = false
    @State private var optimizationRefreshID: UUID = UUID()
    @State private var backupSnapshots: [BackupSnapshotInfo] = []
    @State private var snapshotToRestore: BackupSnapshotInfo?
    @State private var showRestoreConfirmation: Bool = false

    private var isFSRSOptimized: Bool {
        _ = optimizationRefreshID
        return UserDefaults.standard.data(forKey: "fsrsCustomWeights") != nil
    }

    private var fsrsLastOptimizedDate: Date? {
        _ = optimizationRefreshID
        return UserDefaults.standard.object(forKey: "fsrsLastOptimizedDate") as? Date
    }

    private var fsrsLossReduction: Double {
        _ = optimizationRefreshID
        return UserDefaults.standard.double(forKey: "fsrsOptimizedLossReduction")
    }

    private var fsrsSampleCount: Int {
        _ = optimizationRefreshID
        return UserDefaults.standard.integer(forKey: "fsrsOptimizedSampleCount")
    }

    private let accentColors = ["Blue", "Indigo", "Purple", "Orange", "Green", "Teal"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        SettingsSectionMenuView(useFSRS: useFSRS) { sectionID in
                            if reduceMotion {
                                proxy.scrollTo(sectionID, anchor: .top)
                            } else {
                                withAnimation {
                                    proxy.scrollTo(sectionID, anchor: .top)
                                }
                            }
                        }
                    }

                    // Section 1: Appearance
                    Section("Appearance") {
                        Picker("Theme", selection: $appTheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.menu)

                    Picker("Control Color", selection: $appAccentColor) {
                            ForEach(accentColors, id: \.self) { colorName in
                                HStack {
                                    Circle()
                                        .fill(colorForName(colorName))
                                        .frame(width: 14, height: 14)
                                    Text(colorName)
                                }
                                .tag(colorName)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .id("appearance_settings")

                    // Section 2: Study
                    Section("Study") {
                        Picker("Exam goal", selection: $targetExam) {
                            Text("USMLE Step 1").tag("USMLE Step 1")
                            Text("USMLE Step 1 (Pass/Fail)").tag("USMLE Step 1 (Pass/Fail)")
                            Text("USMLE Step 2 CK").tag("USMLE Step 2 CK (Scored)")
                            Text("COMLEX Level 1 / 2").tag("COMLEX Level 1 / 2")
                            Text("Clinical Shelf Exams").tag("Clinical Shelf Exams")
                            Text("MCAT / Pre-Med").tag("MCAT / Pre-Med")
                        }
                        Toggle("Show Study Timer", isOn: $showTimer)
                        Toggle("Auto-advance to Next Card", isOn: $autoAdvance)

                        Stepper("Default New Cards/Day: \(defaultNewCardsPerDay)", value: $defaultNewCardsPerDay, in: 0...100, step: 5)

                        Stepper("Default Max Reviews/Day: \(defaultMaxReviewsPerDay)", value: $defaultMaxReviewsPerDay, in: 0...1000, step: 20)
                    }
                    .id("study_settings")

                    // Section 3: Review & Spaced Repetition (SM-2 vs FSRS)
                    Section {
                        Toggle("Use FSRS Scheduler", isOn: $useFSRS)

                        if useFSRS {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Target Retention")
                                    Spacer()
                                    Text("\(Int(round(fsrsTargetRetention * 100)))%")
                                        .bold()
                                        .foregroundStyle(AppTheme.accent)
                                }

                                Slider(
                                    value: $fsrsTargetRetention,
                                    in: 0.80...0.97,
                                    step: 0.01
                                )
                                .accessibilityLabel("Target Retention")
                                .accessibilityValue("\(Int(round(fsrsTargetRetention * 100))) percent")

                                Text("Recommended: 85%–90% for USMLE Step 1 & 2 exams to maximize recall while avoiding review overload.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            HStack {
                                Text("Learning Steps")
                                Spacer()
                            TextField("Learning Steps", text: $learningSteps)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                            }

                            Stepper("Graduating Interval: \(graduatingInterval) \(graduatingInterval == 1 ? "day" : "days")", value: $graduatingInterval, in: 1...30)

                            Stepper("Easy Interval: \(easyInterval) \(easyInterval == 1 ? "day" : "days")", value: $easyInterval, in: 2...60)
                        }

                        Toggle("Show Next Review Time", isOn: $showNextReviewTime)
                    } header: {
                        Text("Spaced Repetition Algorithm")
                    } footer: {
                        if useFSRS {
                            Text("FSRS-6 (Free Spaced Repetition Scheduler v6 with 21 parameters) replaces static ease factors with continuous memory stability and difficulty modeling, reducing review count by ~30% matching modern Anki 24.04+.")
                        } else {
                            Text("SM-2 is the classic Anki algorithm based on exponential intervals and ease factor adjustments.")
                        }
                    }
                    .id("review_settings")

                    if useFSRS {
                        SettingsFSRSPersonalizationSection(
                            isOptimized: isFSRSOptimized,
                            isOptimizing: isOptimizingFSRS,
                            lossReduction: fsrsLossReduction,
                            sampleCount: fsrsSampleCount,
                            reviewCount: FSRSOptimizer.getReviewCount(context: modelContext),
                            minimumRequiredReviews: FSRSOptimizer.minimumRequiredReviews,
                            onOptimize: runFSRSOptimization,
                            onReset: resetFSRSToDefaults
                        )
                        .id("fsrs_personalization")
                    }

                    // Section: Burnout Shield & Load Balancer (Reddit USMLE Top Request)
                    Section {
                        Toggle("Enable Fuzzy Load Balancer", isOn: $enableLoadBalancer)

                        if enableLoadBalancer {
                            Stepper("Burnout Cap: \(burnoutShieldMaxDaily) reviews/day", value: $burnoutShieldMaxDaily, in: 50...500, step: 25)

                            Button {
                                redistributeAllOverdueCards()
                            } label: {
                                HStack {
                                    Image(systemName: "shield.lefthalf.filled")
                                    Text("Redistribute Overdue Backlog")
                                }
                            }
                        }
                    } header: {
                        Text("Burnout Shield & Load Balancer")
                    } footer: {
                        Text("Fuzzy load balancing smooths daily spikes (±5%). Overdue redistribution spreads backlog cards across 3–7 days after grueling hospital rotations.\n\n⚠️ Tradeoff Note: Spreading overdue cards intentionally deviates from the strict FSRS mathematical retrievability curve to reduce cognitive fatigue.")
                    }
                    .id("burnout_shield")

                    SettingsRemoteSection()
                        .id("bluetooth_settings")

                    // Section 4: Data Management
                    Section("Data Management") {
                        Button {
                            exportAllData()
                        } label: {
                            Label("Export All Data", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import Data", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            SampleMedicalData.loadSampleMedicalDeck(into: modelContext)
                            statusMessage = "Loaded USMLE Step 1 & 2 Demo Deck successfully!"
                            showStatusAlert = true
                        } label: {
                            Label("Load USMLE Step 1 & 2 Demo Deck", systemImage: "cross.case.fill")
                                .foregroundStyle(.blue)
                        }

                    }
                    .id("data_management")

                    // Section 5: Automated Backups & Disaster Recovery
                    Section {
                        Button {
                            do {
                                let url = try BackupManager.shared.createSnapshot(context: modelContext, reason: "Manual")
                                refreshBackupSnapshots()
                                statusMessage = "Backup created: \(url.lastPathComponent)"
                                showStatusAlert = true
                            } catch {
                                statusMessage = "Backup failed: \(error.localizedDescription)"
                                showStatusAlert = true
                            }
                        } label: {
                            Label("Create Instant Backup Snapshot", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                .foregroundStyle(.blue)
                        }

                        if backupSnapshots.isEmpty {
                            Text("No snapshots saved yet. Auto-daily snapshots run automatically.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(backupSnapshots) { snapshot in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(snapshot.reason)
                                                .font(.footnote.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.12))
                                                .foregroundStyle(AppTheme.accent)
                                                .clipShape(Capsule())

                                            Text(snapshot.formattedSize)
                                                .font(.footnote.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(snapshot.creationDate.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline)
                                    }

                                    Spacer()

                                    Button("Restore") {
                                        snapshotToRestore = snapshot
                                        showRestoreConfirmation = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .accessibilityLabel("Restore backup from \(snapshot.creationDate.formatted(date: .abbreviated, time: .shortened))")
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        try? BackupManager.shared.deleteSnapshot(at: snapshot.url)
                                        refreshBackupSnapshots()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Automated Backups & Snapshots")
                    } footer: {
                        Text("Rolling 7-day automated snapshots safeguard your study progress, reviews, and decks against data loss before major board exams.")
                    }
                    .id("backup_settings")

                    // Section 6: iOS 17 Widgets & Badges
                    Section {
                        WidgetPreviewSection()
                    }
                    .id("widgets_settings")

                    // Section: CloudKit Sync (Local-First)
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sync Status")
                                Text(syncManager.syncStatus.displayText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "icloud.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                        .accessibilityElement(children: .combine)

                        Button {
                            Task {
                                await syncManager.triggerSync(context: modelContext)
                            }
                        } label: {
                            HStack {
                                if isSyncing {
                                    ProgressView()
                                        .accessibilityHidden(true)
                                }
                                Text(isSyncing ? "Syncing…" : "Sync Now")
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSyncing)
                        .accessibilityHint(isSyncing ? "Sync is in progress" : "Syncs cards and review history with your private iCloud database")

                        if let lastSync = syncManager.lastSyncDate {
                            LabeledContent("Last Synced", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                        }

                        NavigationLink {
                            CloudSyncAuditView()
                        } label: {
                            Label("Conflict Resolution Audit Log", systemImage: "arrow.triangle.merge")
                        }
                    } header: {
                        Text("CloudKit Multi-Device Sync")
                    } footer: {
                        Text("Cards stay on this iPhone first. Sync Now copies them to your private iCloud database and merges other devices for real. Cards use last-write-wins. Review history is unioned, so a review is never deleted by a conflict. If you are not signed into iCloud, RecallRx will say so instead of pretending the sync worked.")
                    }
                    .id("cloud_sync_settings")

                    // Section: Notifications & Reminders
                    Section {
                        Toggle("Daily Study Reminders", isOn: Binding(
                            get: { NotificationManager.shared.dailyRemindersEnabled },
                            set: { enabled in
                                NotificationManager.shared.dailyRemindersEnabled = enabled
                                if enabled {
                                    Task {
                                        let granted = await notificationManager.requestAuthorization()
                                        if granted {
                                            await LifecycleCoordinator.shared.refresh(context: modelContext)
                                        } else {
                                            notificationManager.dailyRemindersEnabled = false
                                            statusMessage = "Study reminders need notification permission. You can enable it in iOS Settings."
                                            showStatusAlert = true
                                        }
                                    }
                                } else {
                                    NotificationManager.shared.cancelDailyReminder()
                                }
                            }
                        ))

                        if NotificationManager.shared.dailyRemindersEnabled {
                            DatePicker("Reminder Time", selection: Binding(
                                get: {
                                    var comp = DateComponents()
                                    comp.hour = NotificationManager.shared.reminderHour
                                    comp.minute = NotificationManager.shared.reminderMinute
                                    return Calendar.current.date(from: comp) ?? Date()
                                },
                                set: { date in
                                    let comp = Calendar.current.dateComponents([.hour, .minute], from: date)
                                    NotificationManager.shared.reminderHour = comp.hour ?? 20
                                    NotificationManager.shared.reminderMinute = comp.minute ?? 0
                                    NotificationManager.shared.scheduleDailyReminder()
                                }
                            ), displayedComponents: .hourAndMinute)
                        }
                    } header: {
                        Text("Notifications & Daily Reminders")
                    } footer: {
                        Text("Receive gentle daily study notifications to protect your study streak and complete your board cards on time.")
                    }
                    .id("reminder_settings")

                    // Section: Hands-Free Driving Mode Settings
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Silence Timeout")
                                Spacer()
                                Text(String(format: "%.1fs", drivingManager.silenceTimeoutSeconds))
                                    .bold()
                                    .foregroundStyle(.orange)
                            }

                            Slider(
                                value: $drivingManager.silenceTimeoutSeconds,
                                in: 5.0...10.0,
                                step: 0.5
                            )
                            .accessibilityLabel("Silence Timeout")
                            .accessibilityValue("\(drivingManager.silenceTimeoutSeconds.formatted()) seconds")

                            Text("Time to wait after speech before grading answer. Adjust higher for noisy highways or relaxed commutes.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Hands-Free Driving Mode")
                    } footer: {
                        Text("Runs 100% on-device speech synthesis and recognition with zero network usage. Expected answers are passed as contextual vocabulary to overcome road noise.")
                    }
                    .id("driving_settings")

                    // Section: Free Forever Policy & Regional Pricing
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("100% Free Forever Guarantee")
                                    .font(.subheadline.bold())
                            }

                            Text("RecallRx core features are immutable and guaranteed free forever. Zero subscriptions, zero ads, zero gated decks.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            DisclosureGroup("View All 14 Guaranteed Free Features") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(FreeForeverConfig.freeForeverFeatures, id: \.self) { feature in
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark")
                                                .font(.footnote.bold())
                                                .foregroundStyle(.green)
                                            Text(feature)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.subheadline.bold())
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Pricing Policy & Guarantee")
                    }
                    .id("pricing_guarantee")

                    Section {
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Reset All Study Progress", systemImage: "arrow.counterclockwise")
                        }

                        Button(role: .destructive) {
                            showDeleteAllDecksConfirmation = true
                        } label: {
                            Label("Delete All Decks and Cards", systemImage: "trash")
                        }
                    } header: {
                        Text("Reset & Delete")
                    } footer: {
                        Text("These actions cannot be undone. Export your data or create a backup before continuing.")
                    }
                    .id("destructive_settings")

                    // Section 6: About
                    Section("About") {
                        HStack {
                            Text("App Name")
                            Spacer()
                            Text("RecallRx")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0.0 (Build 1)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Spacer()
                            Text("Built with ❤️ for Medical Retention")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Link(destination: URL(string: "https://github.com/thoughtfullyegypt-code/RecallRx")!) {
                            HStack {
                                Text("Source Code & Documentation")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .id("about_settings")
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.canvas)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showExportShareSheet) {
                    if let url = exportedDataURL {
                        ShareActivityView(activityItems: [url])
                    }
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data, .json, .commaSeparatedText, .zip]
                ) { result in
                    handleFileImport(result: result)
                }
                .alert("Reset Progress", isPresented: $showResetConfirmation) {
                    Button("Reset Everything", role: .destructive) {
                        resetAllProgress()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will reset interval, repetitions, ease factors, and review logs for all cards back to the new state. This action cannot be undone.")
                }
                .alert("Delete All Decks", isPresented: $showDeleteAllDecksConfirmation) {
                    Button("Delete All", role: .destructive) {
                        deleteAllDecks()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete all decks and cards permanently? This action cannot be undone.")
                }
                .alert("Status", isPresented: $showStatusAlert) {
                    Button("OK") {}
                } message: {
                    Text(statusMessage ?? "")
                }
                .confirmationDialog(
                    "Restore Backup Snapshot?",
                    isPresented: $showRestoreConfirmation,
                    presenting: snapshotToRestore
                ) { snapshot in
                    Button("Restore and Replace Current Decks", role: .destructive) {
                        do {
                            try BackupManager.shared.restoreSnapshot(from: snapshot.url, context: modelContext)
                            refreshBackupSnapshots()
                            statusMessage = "Database restored successfully from snapshot!"
                            showStatusAlert = true
                        } catch {
                            statusMessage = "Restore failed: \(error.localizedDescription)"
                            showStatusAlert = true
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: { snapshot in
                    Text("This will replace current cards with data from \(snapshot.creationDate.formatted()). A safety backup will be created automatically before restoring.")
                }
                .onAppear {
                    refreshBackupSnapshots()
                    if UserDefaults.standard.bool(forKey: "scrollToAboutSettings") {
                        UserDefaults.standard.removeObject(forKey: "scrollToAboutSettings")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo("about_settings", anchor: .bottom)
                            }
                        }
                    } else if UserDefaults.standard.bool(forKey: "scrollToBluetoothSettings") {
                        UserDefaults.standard.removeObject(forKey: "scrollToBluetoothSettings")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo("bluetooth_settings", anchor: .top)
                            }
                        }
                    } else if UserDefaults.standard.bool(forKey: "scrollToBackupSettings") {
                        UserDefaults.standard.removeObject(forKey: "scrollToBackupSettings")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo("backup_settings", anchor: .top)
                            }
                        }
                    } else if UserDefaults.standard.bool(forKey: "scrollToSyncSettings") {
                        UserDefaults.standard.removeObject(forKey: "scrollToSyncSettings")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo("cloud_sync_settings", anchor: .top)
                            }
                        }
                    } else if UserDefaults.standard.bool(forKey: "scrollToPricingSettings") {
                        UserDefaults.standard.removeObject(forKey: "scrollToPricingSettings")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo("pricing_guarantee", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    private var isSyncing: Bool {
        if case .syncing = syncManager.syncStatus {
            return true
        }
        return false
    }

    // MARK: - Actions

    private func refreshBackupSnapshots() {
        backupSnapshots = BackupManager.shared.listSnapshots()
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "Indigo": return .indigo
        case "Purple": return .purple
        case "Orange": return .orange
        case "Green": return .green
        case "Teal": return AppTheme.accent
        default: return .blue
        }
    }

    private func exportAllData() {
        do {
            let data = try ImportExportManager.exportAllDecks(context: modelContext)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("RecallRx_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json")
            try data.write(to: fileURL)
            exportedDataURL = fileURL
            showExportShareSheet = true
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    private func handleFileImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                statusMessage = "Unable to access selected file."
                showStatusAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let ext = url.pathExtension.lowercased()
                if ext == "apkg" {
                    let result = try ApkgImporter.importApkg(from: url, into: modelContext)
                    statusMessage = result.message
                } else if ext == "csv" {
                    let data = try Data(contentsOf: url)
                    guard let csvString = String(data: data, encoding: .utf8) else {
                        throw ImportError.invalidData
                    }
                    let deckName = url.deletingPathExtension().lastPathComponent
                    _ = try ImportExportManager.importFromCSV(csvString, deckName: deckName, context: modelContext)
                    statusMessage = "CSV successfully imported into '\(deckName)'!"
                } else {
                    let data = try Data(contentsOf: url)
                    _ = try ImportExportManager.importDeck(from: data, context: modelContext)
                    statusMessage = "JSON Deck successfully imported!"
                }
                showStatusAlert = true
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
                showStatusAlert = true
            }
        case .failure(let error):
            statusMessage = "Failed to select file: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    private func resetAllProgress() {
        do {
            let cards = try modelContext.fetch(FetchDescriptor<Card>())
            for card in cards {
                card.state = .new
                card.interval = 0.0
                card.easeFactor = AppConstants.defaultEaseFactor
                card.repetitions = 0
                card.lapseCount = 0
                card.learningStep = 0
                card.dueDate = .now
                card.lastReviewDate = nil
                card.isBuried = false
            }

            let logs = try modelContext.fetch(FetchDescriptor<ReviewLog>())
            for log in logs {
                modelContext.delete(log)
            }

            try modelContext.save()
            statusMessage = "Progress reset successfully for \(cards.count) cards."
            showStatusAlert = true
        } catch {
            statusMessage = "Failed to reset progress: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    private func deleteAllDecks() {
        do {
            let decks = try modelContext.fetch(FetchDescriptor<Deck>())
            for deck in decks {
                modelContext.delete(deck)
            }

            let cards = try modelContext.fetch(FetchDescriptor<Card>())
            for card in cards {
                modelContext.delete(card)
            }

            let logs = try modelContext.fetch(FetchDescriptor<ReviewLog>())
            for log in logs {
                modelContext.delete(log)
            }

            try modelContext.save()
            statusMessage = "All decks and cards have been deleted."
            showStatusAlert = true
        } catch {
            statusMessage = "Failed to delete decks: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }

    private func runFSRSOptimization() {
        isOptimizingFSRS = true
        Task {
            do {
                let result = try await FSRSOptimizer.optimize(context: modelContext)
                await MainActor.run {
                    isOptimizingFSRS = false
                    optimizationRefreshID = UUID()
                    statusMessage = "FSRS parameters optimized successfully!\n\nAnalyzed \(result.sampleCount) review points.\nLog-loss improved by +\(result.formattedReduction) in \(result.durationMs)ms."
                    showStatusAlert = true
                }
            } catch {
                await MainActor.run {
                    isOptimizingFSRS = false
                    statusMessage = "Optimization could not complete: \(error.localizedDescription)"
                    showStatusAlert = true
                }
            }
        }
    }

    private func resetFSRSToDefaults() {
        Scheduler.resetFSRSToDefault()
        optimizationRefreshID = UUID()
        statusMessage = "Reset to standard FSRS parameters."
        showStatusAlert = true
    }

    private func redistributeAllOverdueCards() {
        let descriptor = FetchDescriptor<Deck>()
        let decks = (try? modelContext.fetch(descriptor)) ?? []
        var totalSmoothed = 0
        for deck in decks {
            totalSmoothed += LoadBalancer.redistributeOverdueBacklog(in: deck, maxDailyCap: burnoutShieldMaxDaily, context: modelContext)
        }
        if totalSmoothed > 0 {
            statusMessage = "Burnout Shield smoothed \(totalSmoothed) overdue cards across the upcoming week!"
        } else {
            statusMessage = "All decks are within the daily review cap (\(burnoutShieldMaxDaily) cards). No backlog redistribution required!"
        }
        showStatusAlert = true
    }
}
