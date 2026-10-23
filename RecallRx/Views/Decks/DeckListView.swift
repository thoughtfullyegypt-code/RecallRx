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
        @Bindable var vm = vm
        VStack(spacing: 0) {
            if vm.decks.isEmpty {
                emptyStateView(vm: vm)
            } else {
                deckList(vm: vm)
            }
        }
        .navigationTitle("Decks")
        .searchable(
            text: $vm.searchText,
            prompt: "Search decks"
        )
        .refreshable {
            vm.fetchDecks()
        }
        .background(AppTheme.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Study tools", systemImage: "slider.horizontal.3") {
                    Button("Custom study", systemImage: "flame") {
                        showingShelfCram = true
                    }
                    Button("UWorld incorrects", systemImage: "bolt.badge.automatic") {
                        showingUWorldSync = true
                    }
                    Button("QBank unsuspend", systemImage: "cross.case") {
                        showingQBankTool = true
                    }
                    Button("Cards from notes", systemImage: "doc.badge.plus") {
                        showingPDFGenerator = true
                    }
                }
                Button("New deck", systemImage: "plus", action: showNewDeck)
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
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    // MARK: - Library

    private func deckList(vm: DeckViewModel) -> some View {
        List {
            if vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    DeckLibrarySummaryView(decks: vm.decks)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    CloudSyncStatusPill()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if vm.filteredDecks.isEmpty {
                ContentUnavailableView.search
                    .listRowBackground(Color.clear)
            } else {
                Section {
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
                } header: {
                    Text("Your decks")
                } footer: {
                    Text("New · Learning · Review. Counts include subdecks. Touch and hold a deck for more options.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.canvas)
    }

    private func showNewDeck() {
        selectedParentForSubdeck = nil
        showingAddDeck = true
    }

    // MARK: - Empty State


    @ViewBuilder
    private func emptyStateView(vm: DeckViewModel) -> some View {
        ContentUnavailableView {
            Label("No Decks Yet", systemImage: "square.stack.badge.plus")
        } description: {
            Text("Make a home for your notes, or explore a sample medical deck before adding your own cards.")
        } actions: {
            VStack(spacing: 12) {
                Button {
                    selectedParentForSubdeck = nil
                    showingAddDeck = true
                } label: {
                    Text("Create a deck")
                        .bold()
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    SampleMedicalData.loadSampleMedicalDeck(into: modelContext)
                    vm.fetchDecks()
                } label: {
                    Label("Explore sample cards", systemImage: "cross.case")
                        .bold()
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxHeight: .infinity)
    }

}
