import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedTab: Tab = .decks
    
    @State private var activeSheet: ActiveSheet? = nil
    
    enum Tab: Int, Hashable, CaseIterable {
        case decks = 0
        case add = 1
        case browse = 2
        case stats = 3
    }
    
    enum ActiveSheet: String, Identifiable {
        case settings
        case qbank
        case tags
        case study
        case studyAnswer
        case cardDetail
        case imageOcclusion
        case studyIO
        case studyIOAnswer
        case uworldSync
        case studyRemote
        case shelfCram
        case pdfGenerator
        case drivingMode
        case onboarding
        
        var id: String { rawValue }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DeckListView()
                .tabItem {
                    Label("Decks", systemImage: "house.fill")
                }
                .tag(Tab.decks)
            
            AddCardView()
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(Tab.add)
            
            BrowseView()
                .tabItem {
                    Label("Browse", systemImage: "rectangle.stack.fill")
                }
                .tag(Tab.browse)
            
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
                .tag(Tab.stats)
        }
        .environment(\.modelContext, modelContext)
        .sheet(item: $activeSheet) { sheet in
            sheetDestination(sheet)
        }
        .task {
            let descriptor = FetchDescriptor<Card>()
            let cards = (try? modelContext.fetch(descriptor)) ?? []
            if !cards.contains(where: { $0.noteTypeRaw == NoteType.imageOcclusion.rawValue }) {
                SampleMedicalData.loadSampleMedicalDeck(into: modelContext)
            }
            #if DEBUG
            if CommandLine.arguments.contains("--run-tests") {
                _ = TestRunner.shared.runAllTests(modelContext: modelContext)
            }
            #endif
            monitorCommands()
        }
    }
    
    @ViewBuilder
    private func sheetDestination(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .qbank:
            QBankUnsuspendView()
        case .tags:
            HierarchicalTagView()
        case .study:
            if let deck = fetchFirstDeck() {
                StudyView(deck: deck)
            } else {
                Text("No deck available")
            }
        case .studyAnswer:
            if let deck = fetchFirstDeck() {
                let vm = StudyViewModel(deck: deck, modelContext: modelContext)
                StudyView(deck: deck, viewModel: vm)
                    .onAppear {
                        vm.showAnswer()
                    }
            } else {
                Text("No deck available")
            }
        case .cardDetail:
            if let card = fetchFirstCard() {
                NavigationStack {
                    CardDetailView(card: card)
                }
            } else {
                Text("No card available")
            }
        case .imageOcclusion:
            ImageOcclusionCreatorView()
        case .studyIO:
            if let deck = fetchFirstDeck(),
               let ioCard = deck.cards.first(where: { $0.noteTypeRaw == NoteType.imageOcclusion.rawValue }) {
                let vm = StudyViewModel(deck: deck, modelContext: modelContext)
                StudyView(deck: deck, viewModel: vm)
                    .onAppear {
                        vm.currentCard = ioCard
                        vm.isShowingAnswer = false
                    }
            } else if let deck = fetchFirstDeck() {
                StudyView(deck: deck)
            } else {
                Text("No deck")
            }
        case .studyIOAnswer:
            if let deck = fetchFirstDeck(),
               let ioCard = deck.cards.first(where: { $0.noteTypeRaw == NoteType.imageOcclusion.rawValue }) {
                let vm = StudyViewModel(deck: deck, modelContext: modelContext)
                StudyView(deck: deck, viewModel: vm)
                    .onAppear {
                        vm.currentCard = ioCard
                        vm.isShowingAnswer = true
                    }
            } else if let deck = fetchFirstDeck() {
                StudyView(deck: deck)
            } else {
                Text("No deck")
            }
        case .uworldSync:
            UWorldSyncView(autoLoadSample: true)
        case .studyRemote:
            if let deck = fetchFirstDeck() {
                StudyView(deck: deck)
                    .onAppear {
                        BluetoothControllerManager.shared.simulateConnection(name: "8BitDo Micro (Bluetooth)")
                        BluetoothControllerManager.shared.lastPressedButton = "Button A (Good)"
                        BluetoothControllerManager.shared.lastPressTime = Date()
                    }
            } else {
                Text("No deck")
            }
        case .shelfCram:
            FilteredDeckConfigView()
        case .pdfGenerator:
            PDFImportGeneratorView(autoLoadSample: true)
        case .drivingMode:
            if let deck = fetchFirstDeck() {
                DrivingModeView(deck: deck)
            } else {
                Text("No deck available")
            }
        case .onboarding:
            OnboardingView()
        }
    }
    
    private func fetchFirstDeck() -> Deck? {
        let descriptor = FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.name)])
        let decks = (try? modelContext.fetch(descriptor)) ?? []
        return decks.first(where: { !$0.name.contains("Test") }) ?? decks.first
    }
    
    private func fetchFirstCard() -> Card? {
        let descriptor = FetchDescriptor<Card>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor))?.first
    }
    
    private func applyScreen(_ screen: String) {
        if activeSheet != nil {
            activeSheet = nil
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    presentTargetScreen(screen)
                }
            }
        } else {
            presentTargetScreen(screen)
        }
    }
    
    private func presentTargetScreen(_ screen: String) {
        withAnimation {
            switch screen {
            case "decks":
                activeSheet = nil
                selectedTab = .decks
            case "add":
                activeSheet = nil
                selectedTab = .add
            case "browse":
                activeSheet = nil
                selectedTab = .browse
            case "stats":
                activeSheet = nil
                selectedTab = .stats
            case "settings":
                activeSheet = .settings
            case "fsrs_on":
                UserDefaults.standard.set(true, forKey: "useFSRS")
                UserDefaults.standard.set(0.90, forKey: "fsrsTargetRetention")
                activeSheet = .settings
            case "fsrs_off":
                UserDefaults.standard.set(false, forKey: "useFSRS")
                activeSheet = .settings
            case "qbank":
                activeSheet = .qbank
            case "tags":
                activeSheet = .tags
            case "study":
                activeSheet = .study
            case "study_answer":
                activeSheet = .studyAnswer
            case "card_detail":
                activeSheet = .cardDetail
            case "image_occlusion":
                activeSheet = .imageOcclusion
            case "study_io":
                activeSheet = .studyIO
            case "study_io_answer":
                activeSheet = .studyIOAnswer
            case "uworld_sync":
                activeSheet = .uworldSync
            case "bluetooth_settings":
                UserDefaults.standard.set(true, forKey: "scrollToBluetoothSettings")
                BluetoothControllerManager.shared.simulateConnection(name: "8BitDo Micro (Bluetooth)")
                BluetoothControllerManager.shared.lastPressedButton = "Button A (Good)"
                BluetoothControllerManager.shared.lastPressTime = Date()
                activeSheet = .settings
            case "about_settings":
                UserDefaults.standard.set(true, forKey: "scrollToAboutSettings")
                activeSheet = .settings
            case "backup_settings":
                UserDefaults.standard.set(true, forKey: "scrollToBackupSettings")
                activeSheet = .settings
            case "sync_settings":
                UserDefaults.standard.set(true, forKey: "scrollToSyncSettings")
                activeSheet = .settings
            case "pricing_settings":
                UserDefaults.standard.set(true, forKey: "scrollToPricingSettings")
                activeSheet = .settings
            case "study_remote":
                activeSheet = .studyRemote
            case "shelf_cram":
                activeSheet = .shelfCram
            case "swipe_study":
                activeSheet = .studyAnswer
            case "pdf_generator":
                activeSheet = .pdfGenerator
            case "driving_mode":
                activeSheet = .drivingMode
            case "parked_audit":
                if activeSheet != .drivingMode {
                    activeSheet = .drivingMode
                }
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    NotificationCenter.default.post(name: NSNotification.Name("OpenParkedAudit"), object: nil)
                }
            case "onboarding":
                activeSheet = .onboarding
            case "run_tests":
                _ = TestRunner.shared.runAllTests(modelContext: modelContext)
            default:
                break
            }
        }
    }
    
    private func monitorCommands() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let navFile = docs.appendingPathComponent("navigate.txt")
        
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if let content = try? String(contentsOf: navFile, encoding: .utf8) {
                    let cmd = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cmd.isEmpty {
                        await MainActor.run {
                            applyScreen(cmd)
                        }
                        try? "".write(to: navFile, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
    }
}
