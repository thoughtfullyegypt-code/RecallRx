import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var viewModel: DeckViewModel?
    @State private var showingAddDeck: Bool = false
    @State private var selectedParentForSubdeck: UUID? = nil
    @State private var showingSettings: Bool = false
    @State private var showingQBankTool: Bool = false
    @State private var showingUWorldSync: Bool = false
    @State private var showingShelfCram: Bool = false
    @State private var showingPDFGenerator: Bool = false
    
    @State private var deckToRename: Deck? = nil
    @State private var renameText: String = ""
    @State private var showingRenameAlert: Bool = false
    
    @State private var deckToDelete: Deck? = nil
    @State private var showingDeleteConfirmation: Bool = false
    
    @State private var expandedDeckIDs: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    mainContentView(vm: vm)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            if viewModel == nil {
                let vm = DeckViewModel(modelContext: modelContext)
                if vm.decks.isEmpty {
                    SampleMedicalData.loadSampleMedicalDeck(into: modelContext)
                    vm.fetchDecks()
                }
                viewModel = vm
            } else {
                viewModel?.fetchDecks()
            }
        }
    }
    
    // MARK: - Main Content View
    
    @ViewBuilder
    private func mainContentView(vm: DeckViewModel) -> some View {
        VStack(spacing: 0) {
            if vm.decks.isEmpty {
                emptyStateView(vm: vm)
            } else {
                deckList(vm: vm)
                bottomSummaryBar(vm: vm)
            }
        }
        .navigationTitle("Decks")
        .searchable(
            text: Binding(
                get: { vm.searchText },
                set: { vm.searchText = $0 }
            ),
            prompt: "Search decks"
        )
        .refreshable {
            vm.fetchDecks()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingShelfCram = true
                    } label: {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Shelf Exam Cram & Custom Study")
                    
                    Button {
                        showingUWorldSync = true
                    } label: {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .foregroundColor(.orange)
                    }
                    .accessibilityLabel("UWorld Incorrects Auto-Sync")
                    
                    Button {
                        showingQBankTool = true
                    } label: {
                        Image(systemName: "cross.case.fill")
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("QBank Fast-Unsuspend")
                    
                    Button {
                        showingPDFGenerator = true
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.purple)
                    }
                    .accessibilityLabel("AI PDF Lecture Notes Generator")
                    
                    Button {
                        selectedParentForSubdeck = nil
                        showingAddDeck = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddDeck) {
            AddDeckView(
                viewModel: vm,
                initialParentDeckID: selectedParentForSubdeck
            )
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingQBankTool) {
            QBankUnsuspendView()
        }
        .sheet(isPresented: $showingUWorldSync) {
            UWorldSyncView()
        }
        .sheet(isPresented: $showingShelfCram) {
            FilteredDeckConfigView()
        }
        .sheet(isPresented: $showingPDFGenerator) {
            PDFImportGeneratorView()
        }
        .alert("Rename Deck", isPresented: $showingRenameAlert) {
            TextField("Deck Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let deck = deckToRename {
                    vm.renameDeck(deck, to: renameText)
                }
            }
        }
        .confirmationDialog(
            "Delete Deck",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let deck = deckToDelete {
                Button("Delete '\(deck.name)'", role: .destructive) {
                    vm.deleteDeck(deck)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let deck = deckToDelete {
                Text("Deleting this deck will also delete all of its cards and subdecks. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - List of Decks
    
    @ViewBuilder
    private func deckList(vm: DeckViewModel) -> some View {
        List {
            Section {
                CloudSyncStatusPill()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            ForEach(vm.filteredDecks, id: \.id) { topDeck in
                DeckRowHierarchyView(
                    vm: vm,
                    deck: topDeck,
                    level: 0,
                    expandedDeckIDs: $expandedDeckIDs,
                    deckToRename: $deckToRename,
                    renameText: $renameText,
                    showingRenameAlert: $showingRenameAlert,
                    deckToDelete: $deckToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    selectedParentForSubdeck: $selectedParentForSubdeck,
                    showingAddDeck: $showingAddDeck
                )
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private struct DeckRowHierarchyView: View {
    let vm: DeckViewModel
    let deck: Deck
    let level: Int
    @Binding var expandedDeckIDs: Set<UUID>
    @Binding var deckToRename: Deck?
    @Binding var renameText: String
    @Binding var showingRenameAlert: Bool
    @Binding var deckToDelete: Deck?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var selectedParentForSubdeck: UUID?
    @Binding var showingAddDeck: Bool
    
    var body: some View {
        let subdecks = vm.getSubdecks(for: deck)
        let isExpanded = expandedDeckIDs.contains(deck.id)
        let dueCounts = vm.getDueCount(for: deck)
        
        NavigationLink(destination: DeckDetailView(deck: deck)) {
            DeckRowView(
                deck: deck,
                newCount: dueCounts.new,
                learningCount: dueCounts.learning,
                reviewCount: dueCounts.review,
                indentationLevel: level,
                hasSubdecks: !subdecks.isEmpty,
                isExpanded: isExpanded,
                onToggleExpand: {
                    if isExpanded {
                        expandedDeckIDs.remove(deck.id)
                    } else {
                        expandedDeckIDs.insert(deck.id)
                    }
                }
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deckToDelete = deck
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                deckToRename = deck
                renameText = deck.name
                showingRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                deckToRename = deck
                renameText = deck.name
                showingRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Button {
                selectedParentForSubdeck = deck.id
                showingAddDeck = true
            } label: {
                Label("Add Subdeck", systemImage: "folder.badge.plus")
            }
            
            ShareLink(
                item: ImportExportManager.generateShareText(for: deck),
                subject: Text(deck.name),
                message: Text("RecallRx Deck Summary")
            ) {
                Label("Export / Share", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            Button(role: .destructive) {
                deckToDelete = deck
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        
        if isExpanded {
            ForEach(subdecks, id: \.id) { subdeck in
                DeckRowHierarchyView(
                    vm: vm,
                    deck: subdeck,
                    level: level + 1,
                    expandedDeckIDs: $expandedDeckIDs,
                    deckToRename: $deckToRename,
                    renameText: $renameText,
                    showingRenameAlert: $showingRenameAlert,
                    deckToDelete: $deckToDelete,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    selectedParentForSubdeck: $selectedParentForSubdeck,
                    showingAddDeck: $showingAddDeck
                )
            }
        }
    }
}
    
    // MARK: - Empty State
    
    @ViewBuilder
    private func emptyStateView(vm: DeckViewModel) -> some View {
        ContentUnavailableView {
            Label("No Decks Yet", systemImage: "square.stack.badge.plus")
        } description: {
            Text("Create your first deck or load the high-yield USMLE Step 1 & 2 demo deck.")
        } actions: {
            VStack(spacing: 12) {
                Button {
                    selectedParentForSubdeck = nil
                    showingAddDeck = true
                } label: {
                    Text("Create Deck")
                        .bold()
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button {
                    SampleMedicalData.loadSampleMedicalDeck(into: modelContext)
                    vm.fetchDecks()
                } label: {
                    Label("Load USMLE Demo Deck", systemImage: "cross.case.fill")
                        .bold()
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .controlSize(.large)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Bottom Summary Bar
    
    @ViewBuilder
    private func bottomSummaryBar(vm: DeckViewModel) -> some View {
        let totalCards = vm.decks.reduce(0) { $0 + $1.cards.count }
        let totalNew = vm.decks.reduce(0) { $0 + $1.newCards }
        let totalLearning = vm.decks.reduce(0) { $0 + $1.learningCards }
        let totalReview = vm.decks.reduce(0) { $0 + $1.dueCards }
        let totalDue = totalNew + totalLearning + totalReview
        
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(vm.decks.count) decks • \(totalCards) total cards")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                
                Text("\(totalDue) cards due today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                DeckCountBadge(count: totalNew, color: .blue)
                DeckCountBadge(count: totalLearning, color: .orange)
                DeckCountBadge(count: totalReview, color: .green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }
}

// MARK: - Deck Detail View

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var deck: Deck
    
    @State private var showingOptions: Bool = false
    @State private var showingAddCard: Bool = false
    @State private var showingRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var showingEmptyConfirmation: Bool = false
    @State private var showingCustomStudySheet: Bool = false
    @State private var showingDrivingMode: Bool = false
    @State private var customStudyNewCount: Int = 10
    @State private var customStudyReviewCount: Int = 20
    
    var body: some View {
        List {
            // Study Action Hero Section
            Section {
                studyButtonSection
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            
            // Due & Total Card Counts Overview
            Section("Card Counts") {
                countsGridView
            }
            
            // Cards in this Deck Section
            Section {
                if deck.cards.isEmpty {
                    VStack(spacing: 8) {
                        Text("No cards in this deck yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button {
                            showingAddCard = true
                        } label: {
                            Label("Add First Card", systemImage: "plus.circle.fill")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                } else {
                    ForEach(deck.cards.sorted(by: { $0.createdAt > $1.createdAt })) { card in
                        deckCardRow(card: card)
                    }
                    .onDelete(perform: deleteCards)
                }
            } header: {
                HStack {
                    Text("Cards (\(deck.cards.count))")
                    Spacer()
                    if !deck.cards.isEmpty {
                        Text("Swipe to delete")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(deck.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        showingAddCard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    
                    Menu {
                        Button {
                            showingOptions = true
                        } label: {
                            Label("Deck Options", systemImage: "gearshape")
                        }
                        
                        Button {
                            renameText = deck.name
                            showingRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Button {
                            rebuildDeck()
                        } label: {
                            Label("Rebuild Queue", systemImage: "arrow.clockwise")
                        }
                        
                        Button {
                            showingCustomStudySheet = true
                        } label: {
                            Label("Custom Study", systemImage: "slider.horizontal.3")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingEmptyConfirmation = true
                        } label: {
                            Label("Empty Deck", systemImage: "trash")
                        }
                        .disabled(deck.cards.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            DeckOptionsView(deck: deck) {
                dismiss()
            }
        }
        .sheet(isPresented: $showingAddCard) {
            AddCardView(defaultDeck: deck)
        }
        .sheet(isPresented: $showingCustomStudySheet) {
            customStudyView
        }
        .sheet(isPresented: $showingDrivingMode) {
            DrivingModeView(deck: deck)
        }
        .alert("Rename Deck", isPresented: $showingRenameAlert) {
            TextField("Deck Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    deck.name = trimmed
                    deck.modifiedAt = .now
                    try? modelContext.save()
                }
            }
        }
        .confirmationDialog(
            "Empty Deck",
            isPresented: $showingEmptyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All \(deck.cards.count) Cards", role: .destructive) {
                for card in deck.cards {
                    modelContext.delete(card)
                }
                deck.cards.removeAll()
                deck.modifiedAt = .now
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete all cards in '\(deck.name)'? This action cannot be undone.")
        }
    }
    
    // MARK: - Study Button Section
    
    @ViewBuilder
    private var studyButtonSection: some View {
        let totalDue = deck.totalDueCount
        
        NavigationLink(destination: StudyView(deck: deck)) {
            HStack(spacing: 12) {
                Image(systemName: totalDue > 0 ? "play.circle.fill" : "sparkles")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(totalDue > 0 ? "Study Now" : (deck.cards.isEmpty ? "Deck is Empty" : "Study All Cards"))
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(totalDue > 0 ? "\(totalDue) cards due for review" : (deck.cards.isEmpty ? "Tap '+' to add cards" : "\(deck.cards.count) total cards"))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: totalDue > 0 ? [Color.blue, Color.accentColor] : [Color.gray, Color.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: (totalDue > 0 ? Color.blue : Color.gray).opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(deck.cards.isEmpty)
        .padding(.horizontal)
        .padding(.vertical, 8)
        
        if !deck.cards.isEmpty {
            Button {
                showingDrivingMode = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "car.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hands-Free Driving Mode")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Text("100% on-device voice review • Safe hands-free study")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Counts Grid
    
    @ViewBuilder
    private var countsGridView: some View {
        HStack(spacing: 12) {
            metricItem(title: "New", count: deck.newCards, color: .blue)
            metricItem(title: "Learning", count: deck.learningCards, color: .orange)
            metricItem(title: "Review", count: deck.dueCards, color: .green)
            metricItem(title: "Total", count: deck.totalCards, color: .purple)
        }
        .padding(.vertical, 6)
    }
    
    private func metricItem(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
    
    // MARK: - Card Row
    
    @ViewBuilder
    private func deckCardRow(card: Card) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.front.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                Text(card.state.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cardStateColor(card.state).opacity(0.15))
                    .foregroundColor(cardStateColor(card.state))
                    .clipShape(Capsule())
            }
            
            if !card.back.isEmpty {
                Text(card.back.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            if !card.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(card.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func cardStateColor(_ state: CardState) -> Color {
        switch state {
        case .new: return .blue
        case .learning, .relearning: return .orange
        case .review: return .green
        }
    }
    
    private func deleteCards(at offsets: IndexSet) {
        let sortedCards = deck.cards.sorted(by: { $0.createdAt > $1.createdAt })
        for index in offsets {
            let card = sortedCards[index]
            modelContext.delete(card)
        }
        try? modelContext.save()
    }
    
    private func rebuildDeck() {
        Scheduler.unburyAllCards(in: deck)
        deck.modifiedAt = .now
        try? modelContext.save()
    }
    
    // MARK: - Custom Study View
    
    private var customStudyView: some View {
        NavigationStack {
            Form {
                Section("Increase Today's Study Limits") {
                    Stepper("Extra New Cards: \(customStudyNewCount)", value: $customStudyNewCount, in: 0...100, step: 5)
                    Stepper("Extra Review Cards: \(customStudyReviewCount)", value: $customStudyReviewCount, in: 0...500, step: 10)
                }
                
                Section {
                    Button("Apply and Start Study") {
                        deck.newCardsPerDay += customStudyNewCount
                        deck.reviewsPerDay += customStudyReviewCount
                        try? modelContext.save()
                        showingCustomStudySheet = false
                    }
                    .bold()
                }
            }
            .navigationTitle("Custom Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingCustomStudySheet = false
                    }
                }
            }
        }
    }
}

// MARK: - Cloud Sync Status Pill

struct CloudSyncStatusPill: View {
    @ObservedObject private var syncManager = CloudSyncManager.shared
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            
            Text(syncManager.syncStatus.displayText)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if case .error = syncManager.syncStatus {
                Button("Retry") {
                    Task {
                        await syncManager.triggerSync(context: modelContext)
                    }
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(.red)
            } else if case .syncing = syncManager.syncStatus {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button {
                    Task {
                        await syncManager.triggerSync(context: modelContext)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch syncManager.syncStatus {
        case .idle:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundColor(.blue)
                .font(.caption)
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                .foregroundColor(.blue)
                .font(.caption)
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .offline:
            Image(systemName: "icloud.slash.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundColor(.red)
                .font(.caption)
        }
    }
}
