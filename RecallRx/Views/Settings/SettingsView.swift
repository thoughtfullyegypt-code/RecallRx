import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // MARK: - AppStorage Settings
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("appAccentColor") private var appAccentColor: String = "Blue"
    
    // Study Settings
    @AppStorage("showTimer") private var showTimer: Bool = true
    @AppStorage("autoAdvance") private var autoAdvance: Bool = false
    @AppStorage("defaultNewCardsPerDay") private var defaultNewCardsPerDay: Int = 20
    @AppStorage("defaultMaxReviewsPerDay") private var defaultMaxReviewsPerDay: Int = 200

    // Review Settings
    @AppStorage("useFSRS") private var useFSRS: Bool = true
    @AppStorage("fsrsTargetRetention") private var fsrsTargetRetention: Double = 0.90
    @AppStorage("showNextReviewTime") private var showNextReviewTime: Bool = true
    @AppStorage("learningSteps") private var learningSteps: String = "1m 10m"
    @AppStorage("graduatingInterval") private var graduatingInterval: Int = 1
    @AppStorage("easyInterval") private var easyInterval: Int = 4
    
    // Medical Unfair Advantages & Remotes
    @ObservedObject private var remoteManager = BluetoothControllerManager.shared
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
                // Section 1: Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.menu)

                    Picker("Accent Color", selection: $appAccentColor) {
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

                // Section 2: Study
                Section("Study") {
                    Toggle("Show Study Timer", isOn: $showTimer)
                    Toggle("Auto-advance to Next Card", isOn: $autoAdvance)

                    Stepper("Default New Cards/Day: \(defaultNewCardsPerDay)", value: $defaultNewCardsPerDay, in: 0...100, step: 5)

                    Stepper("Default Max Reviews/Day: \(defaultMaxReviewsPerDay)", value: $defaultMaxReviewsPerDay, in: 0...1000, step: 20)
                }

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
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(
                                value: $fsrsTargetRetention,
                                in: 0.80...0.97,
                                step: 0.01
                            )
                            
                            Text("Recommended: 85%–90% for USMLE Step 1 & 2 exams to maximize recall while avoiding review overload.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            Text("Learning Steps")
                            Spacer()
                            TextField("Steps", text: $learningSteps)
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

                // Section 3b: FSRS Weight Personalization (Only visible when FSRS is enabled)
                if useFSRS {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Memory Parameters", systemImage: "brain.head.profile")
                                    .font(.headline)
                                Spacer()
                                if isFSRSOptimized {
                                    Text("Personalized")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.18))
                                        .foregroundColor(.green)
                                        .clipShape(Capsule())
                                } else {
                                    Text("Default Weights")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.15))
                                        .foregroundColor(.secondary)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            if isFSRSOptimized {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Predictive Accuracy")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("+\(String(format: "%.1f", fsrsLossReduction))% Log-Loss")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.green)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Trained Reviews")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(fsrsSampleCount) reviews")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }
                                }
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                            
                            let reviewCount = FSRSOptimizer.getReviewCount(context: modelContext)
                            let minRequired = FSRSOptimizer.minimumRequiredReviews
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Statistical Significance Guard")
                                        .font(.caption2.bold())
                                    Spacer()
                                    Text("\(reviewCount) / \(minRequired) reviews")
                                        .font(.caption2.bold())
                                        .foregroundColor(reviewCount >= minRequired ? .green : .secondary)
                                }
                                
                                ProgressView(value: min(1.0, Double(reviewCount) / Double(minRequired)))
                                    .tint(reviewCount >= minRequired ? .green : .blue)
                                
                                Text(reviewCount >= minRequired 
                                     ? "Sufficient review history gathered to personalize stability and difficulty parameters."
                                     : "Requires at least 1,000 real reviews to prevent overfitting. Standard community-calibrated weights are safely utilized until then.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            
                            Button {
                                runFSRSOptimization()
                            } label: {
                                HStack {
                                    if isOptimizingFSRS {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(0.8)
                                        Text("Optimizing Parameters...")
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                        Text(reviewCount >= minRequired ? (isFSRSOptimized ? "Re-optimize FSRS Parameters" : "Optimize FSRS Parameters") : "Optimize FSRS (Requires 1,000 Reviews)")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isOptimizingFSRS || reviewCount < minRequired)
                            
                            if isFSRSOptimized {
                                Button(role: .destructive) {
                                    resetFSRSToDefaults()
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Reset to Standard FSRS-5 Weights")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .font(.caption)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("FSRS Weight Personalization")
                    } footer: {
                        Text("Calculated completely on-device without network calls or cloud telemetry.")
                    }
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

                // Section: Bluetooth Remote & Gamepads (8BitDo Micro / Zero 2 / Joy-Cons)
                Section {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remoteManager.controllerName)
                                    .font(.subheadline.weight(.medium))
                                Text(remoteManager.isConnected ? "Ready for hands-free study" : "No device connected")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundColor(remoteManager.isConnected ? .green : .secondary)
                        }
                        
                        Spacer()
                        
                        Text(remoteManager.isConnected ? "Connected" : "Disconnected")
                            .font(.caption2.bold())
                            .foregroundColor(remoteManager.isConnected ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((remoteManager.isConnected ? Color.green : Color.secondary).opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    // Live Controller Test HUD
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Remote Input Monitor")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Last Pressed:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(remoteManager.lastPressedButton)
                                .font(.caption.monospaced().bold())
                                .foregroundColor(.blue)
                            Spacer()
                            if remoteManager.lastPressedButton != "None" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        
                        // Test press buttons
                        HStack(spacing: 8) {
                            Button("Test A") {
                                remoteManager.handleButtonPress(name: "Button A", actionKey: remoteManager.buttonAAction)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            
                            Button("Test B") {
                                remoteManager.handleButtonPress(name: "Button B", actionKey: remoteManager.buttonBAction)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            
                            Button("Test X") {
                                remoteManager.handleButtonPress(name: "Button X", actionKey: remoteManager.buttonXAction)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                            
                            Button("Test Y") {
                                remoteManager.handleButtonPress(name: "Button Y", actionKey: remoteManager.buttonYAction)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption2)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Button Customization Mappings
                    NavigationLink {
                        RemoteButtonMappingView()
                    } label: {
                        Label("Customize Remote Buttons", systemImage: "slider.horizontal.3")
                    }
                    
                    // Simulation toggle for testing
                    Button {
                        if remoteManager.isConnected {
                            remoteManager.simulateDisconnection()
                        } else {
                            remoteManager.simulateConnection(name: "8BitDo Micro (Bluetooth)")
                        }
                    } label: {
                        HStack {
                            Image(systemName: remoteManager.isConnected ? "bolt.slash" : "bolt.fill")
                            Text(remoteManager.isConnected ? "Disconnect Remote" : "Simulate 8BitDo Micro Connected")
                        }
                        .font(.caption)
                    }
                } header: {
                    Text("Bluetooth Remote & Gamepads")
                } footer: {
                    Text("Compatible with 8BitDo Micro, 8BitDo Zero 2, Joy-Cons, Xbox, and PS controllers. For 8BitDo Micro, switch to D-mode (D+Home) for Gamepad mode or K-mode for keyboard keystrokes.")
                }
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

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.orange)
                    }

                    Button(role: .destructive) {
                        showDeleteAllDecksConfirmation = true
                    } label: {
                        Label("Delete All Decks", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

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
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(backupSnapshots) { snapshot in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(snapshot.reason)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundColor(.blue)
                                            .clipShape(Capsule())
                                        
                                        Text(snapshot.formattedSize)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
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
                                .controlSize(.small)
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

                // Section: CloudKit Sync (Local-First)
                Section {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync Status")
                                    .font(.subheadline.bold())
                                Text(CloudSyncManager.shared.syncStatus.displayText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "icloud.fill")
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button("Sync Now") {
                            Task {
                                await CloudSyncManager.shared.triggerSync(context: modelContext)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if let lastSync = CloudSyncManager.shared.lastSyncDate {
                        HStack {
                            Text("Last Synced")
                                .font(.caption)
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
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
                                    _ = await NotificationManager.shared.requestAuthorization()
                                    NotificationManager.shared.scheduleDailyReminder(dueCount: 42, streakDays: 7)
                                }
                            } else {
                                NotificationManager.shared.cancelDailyReminder()
                            }
                        }
                    ))
                    
                    if NotificationManager.shared.dailyRemindersEnabled {
                        HStack {
                            Text("Reminder Time")
                            Spacer()
                            DatePicker("", selection: Binding(
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
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Notifications & Daily Reminders")
                } footer: {
                    Text("Receive gentle daily study notifications to protect your study streak and complete your board cards on time.")
                }

                // Section: Hands-Free Driving Mode Settings
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Silence Timeout")
                            Spacer()
                            Text(String(format: "%.1fs", drivingManager.silenceTimeoutSeconds))
                                .bold()
                                .foregroundColor(.orange)
                        }
                        
                        Slider(
                            value: $drivingManager.silenceTimeoutSeconds,
                            in: 5.0...10.0,
                            step: 0.5
                        )
                        
                        Text("Time to wait after speech before grading answer. Adjust higher for noisy highways or relaxed commutes.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Hands-Free Driving Mode")
                } footer: {
                    Text("Runs 100% on-device speech synthesis and recognition with zero network usage. Expected answers are passed as contextual vocabulary to overcome road noise.")
                }

                // Section: Free Forever Policy & Regional Pricing
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("100% Free Forever Guarantee")
                                .font(.subheadline.bold())
                        }
                        
                        Text("RecallRx core features are immutable and guaranteed free forever. Zero subscriptions, zero ads, zero gated decks.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        DisclosureGroup("View All 14 Guaranteed Free Features") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(FreeForeverConfig.freeForeverFeatures, id: \.self) { feature in
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                            .foregroundColor(.green)
                                        Text(feature)
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption.bold())
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Pricing Policy & Guarantee")
                }
                .id("pricing_guarantee")

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

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("Source Code & Documentation")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://apps.apple.com")!) {
                        HStack {
                            Text("Rate RecallRx")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .id("about_settings")
            }
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
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("about_settings", anchor: .bottom)
                        }
                    }
                } else if UserDefaults.standard.bool(forKey: "scrollToBluetoothSettings") {
                    UserDefaults.standard.removeObject(forKey: "scrollToBluetoothSettings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("bluetooth_settings", anchor: .top)
                        }
                    }
                } else if UserDefaults.standard.bool(forKey: "scrollToBackupSettings") {
                    UserDefaults.standard.removeObject(forKey: "scrollToBackupSettings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("backup_settings", anchor: .top)
                        }
                    }
                } else if UserDefaults.standard.bool(forKey: "scrollToSyncSettings") {
                    UserDefaults.standard.removeObject(forKey: "scrollToSyncSettings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("cloud_sync_settings", anchor: .top)
                        }
                    }
                } else if UserDefaults.standard.bool(forKey: "scrollToPricingSettings") {
                    UserDefaults.standard.removeObject(forKey: "scrollToPricingSettings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("pricing_guarantee", anchor: .top)
                        }
                    }
                } else if useFSRS {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("fsrs_personalization", anchor: .top)
                        }
                    }
                }
            }
            }
        }
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
        case "Teal": return .teal
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
        statusMessage = "Reset to standard FSRS v5 open-spaced-repetition parameters."
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

// MARK: - Remote Button Customization View

struct RemoteButtonMappingView: View {
    @AppStorage("remoteButtonAAction") var buttonAAction: String = "good"
    @AppStorage("remoteButtonBAction") var buttonBAction: String = "again"
    @AppStorage("remoteButtonXAction") var buttonXAction: String = "hard"
    @AppStorage("remoteButtonYAction") var buttonYAction: String = "easy"
    @AppStorage("remoteDpadDownAction") var dpadDownAction: String = "showAnswer"
    @AppStorage("remoteL1Action") var l1Action: String = "undo"
    @AppStorage("remoteR1Action") var r1Action: String = "bury"
    
    let options = [
        ("showAnswer", "Show Answer"),
        ("again", "Again (Rating 1)"),
        ("hard", "Hard (Rating 2)"),
        ("good", "Good (Rating 3)"),
        ("easy", "Easy (Rating 4)"),
        ("undo", "Undo Last Review"),
        ("bury", "Bury Card")
    ]
    
    var body: some View {
        Form {
            Section("Face Buttons (8BitDo / Gamepad)") {
                picker(title: "Button A", selection: $buttonAAction)
                picker(title: "Button B", selection: $buttonBAction)
                picker(title: "Button X", selection: $buttonXAction)
                picker(title: "Button Y", selection: $buttonYAction)
            }
            
            Section("D-Pad & Shoulder Bumpers") {
                picker(title: "D-Pad Down", selection: $dpadDownAction)
                picker(title: "L1 / Left Shoulder", selection: $l1Action)
                picker(title: "R1 / Right Shoulder", selection: $r1Action)
            }
            
            Section("Keyboard Mode (K-Mode) Shortcuts") {
                HStack {
                    Text("Space")
                    Spacer()
                    Text("Show Answer / Good")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("1")
                    Spacer()
                    Text("Again")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("2")
                    Spacer()
                    Text("Hard")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("3")
                    Spacer()
                    Text("Good")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("4")
                    Spacer()
                    Text("Easy")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Z")
                    Spacer()
                    Text("Undo")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Button Mappings")
    }
    
    private func picker(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.0) { opt in
                Text(opt.1).tag(opt.0)
            }
        }
    }
}

// MARK: - UIActivityViewController Wrapper for SwiftUI

struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Cloud Sync Conflict Audit View

struct CloudSyncAuditView: View {
    @ObservedObject private var syncManager = CloudSyncManager.shared
    
    var body: some View {
        List {
            if syncManager.conflictAuditLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title)
                    Text("No Sync Conflicts")
                        .font(.headline)
                    Text("All local and remote devices synchronized cleanly without timestamp collisions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                ForEach(syncManager.conflictAuditLog) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.entityType)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(entry.summary)
                            .font(.caption)
                        
                        Text("Strategy: \(entry.strategyApplied)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Conflict Audit Log")
    }
}
