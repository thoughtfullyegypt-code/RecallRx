import SwiftUI
import SwiftData

struct BrowseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Deck.name) private var decks: [Deck]

    @State private var viewModel: BrowseViewModel?
    @State private var isSelectionMode = false
    @State private var cardToEdit: Card?
    @State private var showCreateCard = false
    @State private var showMoveDeckSheet = false
    @State private var showAddTagAlert = false
    @State private var newTagInput = ""
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteIDs: Set<UUID> = []
    @State private var showHierarchicalTagsSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    contentBody(viewModel: vm)
                } else {
                    ProgressView("Loading your library…")
                }
            }
            .navigationTitle("Library")
            .toolbar { toolbarItems }
            .searchable(text: searchTextBinding, prompt: "Search questions, answers, or tags")
            .task {
                if viewModel == nil {
                    viewModel = BrowseViewModel(modelContext: modelContext)
                } else {
                    viewModel?.fetchCards()
                }
            }
            .sheet(item: $cardToEdit, onDismiss: refreshCards) { card in
                CardEditorView(card: card)
            }
            .sheet(isPresented: $showCreateCard, onDismiss: refreshCards) {
                CardEditorView(defaultDeck: viewModel?.selectedDeck)
            }
            .sheet(isPresented: $showMoveDeckSheet) {
                if let vm = viewModel {
                    moveDeckSheet(viewModel: vm)
                }
            }
            .sheet(isPresented: $showHierarchicalTagsSheet, onDismiss: refreshCards) {
                HierarchicalTagView()
            }
            .alert("Add a tag", isPresented: $showAddTagAlert) {
                TextField("Tag name", text: $newTagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add Tag", action: addTagToSelection)
                    .disabled(newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { newTagInput = "" }
            } message: {
                Text("Apply a tag to \(viewModel?.selectedCards.count ?? 0) selected cards.")
            }
            .alert("Delete cards?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deletePendingCards)
                Button("Cancel", role: .cancel) { pendingDeleteIDs.removeAll() }
            } message: {
                Text("This permanently deletes ^[\(pendingDeleteIDs.count) card](inflect: true) and their review history. This cannot be undone.")
            }
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel?.searchText ?? "" },
            set: { viewModel?.searchText = $0 }
        )
    }

    private func contentBody(viewModel: BrowseViewModel) -> some View {
        VStack(spacing: 0) {
            filterBar(viewModel: viewModel)
            if viewModel.filteredCards.isEmpty {
                emptyStateView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cardList(viewModel: viewModel)
            }
        }
        .background(AppTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectionMode && !viewModel.selectedCards.isEmpty {
                batchActionBar(viewModel: viewModel)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelectionMode)
    }

    private func filterBar(viewModel: BrowseViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BrowseFilterChip(
                        title: "All decks",
                        systemImage: "square.stack.3d.up",
                        isSelected: viewModel.selectedDeck == nil
                    ) { viewModel.selectedDeck = nil }

                    ForEach(decks, id: \.id) { deck in
                        BrowseFilterChip(
                            title: deck.displayName,
                            systemImage: "folder",
                            isSelected: viewModel.selectedDeck?.id == deck.id
                        ) {
                            viewModel.selectedDeck = viewModel.selectedDeck?.id == deck.id ? nil : deck
                        }
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Menu {
                    Picker("Card state", selection: Bindable(viewModel).selectedState) {
                        Text("All states").tag(CardState?.none)
                        ForEach(CardState.allCases) { state in
                            Text(state.displayName).tag(Optional(state))
                        }
                    }
                    Picker("Tag", selection: Bindable(viewModel).selectedTag) {
                        Text("All tags").tag(String?.none)
                        ForEach(viewModel.allTags, id: \.self) { tag in
                            Text(tag).tag(Optional(tag))
                        }
                    }
                    if hasFilters(viewModel) {
                        Divider()
                        Button("Clear Filters", systemImage: "xmark.circle") {
                            clearFilters(viewModel)
                        }
                    }
                } label: {
                    Label(filterTitle(viewModel), systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }

                Spacer()

                if viewModel.isSearching {
                    ProgressView()
                        .accessibilityLabel("Searching cards")
                } else {
                    Text("\(viewModel.filteredCards.count) cards")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func cardList(viewModel: BrowseViewModel) -> some View {
        List {
            if isSelectionMode {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.selectedCards.count) selected")
                            .font(.headline)
                        Button("Select or deselect all results") {
                            viewModel.toggleSelectAll()
                        }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                    }
                }
            }

            Section {
                ForEach(viewModel.displayedCards, id: \.id) { card in
                    cardRow(card: card, viewModel: viewModel)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                requestDelete([card.id])
                            }
                            Button(
                                card.isSuspended ? "Resume" : "Suspend",
                                systemImage: card.isSuspended ? "play.circle" : "pause.circle"
                            ) {
                                if card.isSuspended {
                                    viewModel.unsuspendCards([card.id])
                                } else {
                                    viewModel.suspendCards([card.id])
                                }
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button("Edit", systemImage: "pencil") { cardToEdit = card }
                                            }
                }

                if viewModel.hasMoreCards {
                    Button("Load more cards", systemImage: "arrow.down.circle") {
                        viewModel.loadMoreCards()
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            } footer: {
                if viewModel.hasMoreCards {
                    Text("Showing \(viewModel.displayedCards.count) of \(viewModel.filteredCards.count) cards")
                } else if !isSelectionMode {
                    Text("Open a card to see its answer, edit it, or review its history.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { viewModel.fetchCards() }
    }

    @ViewBuilder
    private func cardRow(card: Card, viewModel: BrowseViewModel) -> some View {
        if isSelectionMode {
            let isSelected = viewModel.selectedCards.contains(card.id)
            Button {
                if isSelected {
                    viewModel.selectedCards.remove(card.id)
                } else {
                    viewModel.selectedCards.insert(card.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                        .accessibilityHidden(true)
                    BrowseCardRow(card: card)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to change selection")
        } else {
            NavigationLink(destination: CardDetailView(card: card)) {
                BrowseCardRow(card: card)
            }
        }
    }

    private func batchActionBar(viewModel: BrowseViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions for \(viewModel.selectedCards.count) selected cards")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                Menu("Study status", systemImage: "pause.circle") {
                    Button("Suspend", systemImage: "pause.circle") {
                        viewModel.suspendCards(viewModel.selectedCards)
                    }
                    Button("Resume", systemImage: "play.circle") {
                        viewModel.unsuspendCards(viewModel.selectedCards)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)

                Button("Tag", systemImage: "tag") { showAddTagAlert = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Move", systemImage: "folder") { showMoveDeckSheet = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    requestDelete(viewModel.selectedCards)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private func moveDeckSheet(viewModel: BrowseViewModel) -> some View {
        NavigationStack {
            List(decks, id: \.id) { deck in
                Button {
                    viewModel.moveCards(viewModel.selectedCards, to: deck)
                    showMoveDeckSheet = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(deck.name, systemImage: "folder")
                            .foregroundStyle(.primary)
                        Text("\(deck.cards.count) cards")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Move to deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showMoveDeckSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyStateView(viewModel: BrowseViewModel) -> some View {
        if !viewModel.searchText.isEmpty {
            ContentUnavailableView.search
        } else if hasFilters(viewModel) {
            ContentUnavailableView {
                Label("No matching cards", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try a different deck, card state, or tag.")
            } actions: {
                Button("Clear Filters") { clearFilters(viewModel) }
                    .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView {
                Label("Your library starts here", systemImage: "rectangle.stack")
            } description: {
                Text("Create a card with one question and one clear answer.")
            } actions: {
                Button("Create a Card", systemImage: "plus") { showCreateCard = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let vm = viewModel {
                Menu("Library options", systemImage: "ellipsis.circle") {
                    Picker("Sort by", selection: Bindable(vm).sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    Button(
                        vm.sortAscending ? "Sort Descending" : "Sort Ascending",
                        systemImage: vm.sortAscending ? "arrow.down" : "arrow.up"
                    ) { vm.sortAscending.toggle() }
                    Divider()
                    Button("Explore Tags", systemImage: "tag") { showHierarchicalTagsSheet = true }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelectionMode ? "Done" : "Select", action: toggleSelectionMode)
                .disabled(viewModel?.cards.isEmpty != false)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add Card", systemImage: "plus") { showCreateCard = true }
                .disabled(isSelectionMode)
        }
    }

    private func hasFilters(_ viewModel: BrowseViewModel) -> Bool {
        viewModel.selectedDeck != nil || viewModel.selectedState != nil || viewModel.selectedTag != nil
    }

    private func filterTitle(_ viewModel: BrowseViewModel) -> String {
        let count = [viewModel.selectedState != nil, viewModel.selectedTag != nil].filter { $0 }.count
        return count == 0 ? "Filters" : "Filters (\(count))"
    }

    private func clearFilters(_ viewModel: BrowseViewModel) {
        viewModel.selectedDeck = nil
        viewModel.selectedState = nil
        viewModel.selectedTag = nil
    }

    private func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode { viewModel?.selectedCards.removeAll() }
    }

    private func refreshCards() {
        viewModel?.fetchCards()
    }

    private func addTagToSelection() {
        guard let viewModel else { return }
        viewModel.addTag(newTagInput, to: viewModel.selectedCards)
        newTagInput = ""
    }

    private func requestDelete(_ ids: Set<UUID>) {
        pendingDeleteIDs = ids
        showDeleteConfirmation = true
    }

    private func deletePendingCards() {
        viewModel?.deleteCards(pendingDeleteIDs)
        pendingDeleteIDs.removeAll()
    }
}
