import SwiftUI
import SwiftData

struct BrowseView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.name) private var decks: [Deck]

    @State private var viewModel: BrowseViewModel?
    @State private var isSelectionMode: Bool = false
    @State private var cardToEdit: Card?
    @State private var showMoveDeckSheet: Bool = false
    @State private var showAddTagAlert: Bool = false
    @State private var newTagInput: String = ""
    @State private var showDeleteBatchAlert: Bool = false
    @State private var showHierarchicalTagsSheet: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    contentBody(viewModel: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarItems
            }
            .searchable(
                text: searchTextBinding,
                prompt: "Search front, back, or tag"
            )
            .task {
                if viewModel == nil {
                    viewModel = BrowseViewModel(modelContext: modelContext)
                }
            }
            .sheet(item: $cardToEdit) { card in
                CardEditorView(card: card)
            }
            .sheet(isPresented: $showMoveDeckSheet) {
                if let vm = viewModel {
                    moveDeckSheet(viewModel: vm)
                }
            }
            .sheet(isPresented: $showHierarchicalTagsSheet) {
                HierarchicalTagView()
            }
            .alert("Add Tag to Selected Cards", isPresented: $showAddTagAlert) {
                TextField("Tag name", text: $newTagInput)
                    .textInputAutocapitalization(.never)
                Button("Add") {
                    if let vm = viewModel, !newTagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        vm.addTag(newTagInput, to: vm.selectedCards)
                        newTagInput = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newTagInput = ""
                }
            } message: {
                Text("Enter a tag to apply to the \(viewModel?.selectedCards.count ?? 0) selected card(s).")
            }
            .alert("Delete Cards", isPresented: $showDeleteBatchAlert) {
                Button("Delete", role: .destructive) {
                    if let vm = viewModel {
                        vm.deleteCards(vm.selectedCards)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \(viewModel?.selectedCards.count ?? 0) card(s)? This cannot be undone.")
            }
        }
    }

    // MARK: - Search Binding

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { viewModel?.searchText ?? "" },
            set: { viewModel?.searchText = $0 }
        )
    }

    // MARK: - Content Body

    @ViewBuilder
    private func contentBody(viewModel: BrowseViewModel) -> some View {
        VStack(spacing: 0) {
            // Filter Bar
            filterBar(viewModel: viewModel)
                .background(Color(uiColor: .systemGroupedBackground))

            // Card List / Empty State
            if viewModel.filteredCards.isEmpty {
                emptyStateView(viewModel: viewModel)
            } else {
                cardList(viewModel: viewModel)
            }

            // Multi-Select Action Bar (Bottom)
            if isSelectionMode && !viewModel.selectedCards.isEmpty {
                batchActionBar(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelectionMode)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedCards.count)
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private func filterBar(viewModel: BrowseViewModel) -> some View {
        VStack(spacing: 8) {
            // Deck Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(
                        title: "All Decks",
                        isSelected: viewModel.selectedDeck == nil,
                        icon: "square.stack.3d.up.fill"
                    ) {
                        viewModel.selectedDeck = nil
                    }

                    ForEach(decks, id: \.id) { deck in
                        filterChip(
                            title: deck.name,
                            isSelected: viewModel.selectedDeck?.id == deck.id,
                            icon: "folder.fill"
                        ) {
                            if viewModel.selectedDeck?.id == deck.id {
                                viewModel.selectedDeck = nil
                            } else {
                                viewModel.selectedDeck = deck
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // State & Tag Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // State chips
                    filterChip(
                        title: "All States",
                        isSelected: viewModel.selectedState == nil,
                        icon: "circle.grid.2x2.fill"
                    ) {
                        viewModel.selectedState = nil
                    }

                    ForEach(CardState.allCases) { state in
                        filterChip(
                            title: state.displayName,
                            isSelected: viewModel.selectedState == state,
                            icon: "circle.circle.fill",
                            activeColor: stateColor(state)
                        ) {
                            if viewModel.selectedState == state {
                                viewModel.selectedState = nil
                            } else {
                                viewModel.selectedState = state
                            }
                        }
                    }

                    // Tag Menu
                    Menu {
                        Button("All Tags") {
                            viewModel.selectedTag = nil
                        }

                        if !viewModel.allTags.isEmpty {
                            Divider()
                            ForEach(viewModel.allTags, id: \.self) { tag in
                                Button(tag) {
                                    viewModel.selectedTag = tag
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                            Text(viewModel.selectedTag ?? "Tags")
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(viewModel.selectedTag != nil ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                        .foregroundStyle(viewModel.selectedTag != nil ? Color.white : Color.primary)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private func filterChip(
        title: String,
        isSelected: Bool,
        icon: String? = nil,
        activeColor: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? activeColor : Color(uiColor: .secondarySystemFill))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card List

    @ViewBuilder
    private func cardList(viewModel: BrowseViewModel) -> some View {
        List {
            Section {
                if isSelectionMode {
                    HStack {
                        Text("\(viewModel.selectedCards.count) of \(viewModel.filteredCards.count) selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(viewModel.selectedCards.count == viewModel.filteredCards.count ? "Deselect All" : "Select All") {
                            viewModel.toggleSelectAll()
                        }
                        .font(.subheadline.bold())
                    }
                    .padding(.vertical, 2)
                }

                ForEach(viewModel.displayedCards, id: \.id) { card in
                    cardRowView(card: card, viewModel: viewModel)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.deleteCards([card.id])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                if card.isSuspended {
                                    viewModel.unsuspendCards([card.id])
                                } else {
                                    viewModel.suspendCards([card.id])
                                }
                            } label: {
                                Label(
                                    card.isSuspended ? "Unsuspend" : "Suspend",
                                    systemImage: card.isSuspended ? "play.circle" : "pause.circle"
                                )
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                cardToEdit = card
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }

                // Batch pagination control
                if viewModel.hasMoreCards {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.loadMoreCards()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Load More (\(viewModel.displayedCards.count) of \(viewModel.filteredCards.count))")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
            } header: {
                HStack {
                    if viewModel.displayedCards.count < viewModel.filteredCards.count {
                        Text("Showing \(viewModel.displayedCards.count) of \(viewModel.filteredCards.count) Cards")
                    } else {
                        Text("\(viewModel.filteredCards.count) Cards")
                    }

                    Spacer()

                    if viewModel.isSearching {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Card Row View

    @ViewBuilder
    private func cardRowView(card: Card, viewModel: BrowseViewModel) -> some View {
        if isSelectionMode {
            Button {
                if viewModel.selectedCards.contains(card.id) {
                    viewModel.selectedCards.remove(card.id)
                } else {
                    viewModel.selectedCards.insert(card.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.selectedCards.contains(card.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(viewModel.selectedCards.contains(card.id) ? Color.accentColor : Color.secondary)

                    cardRowContent(card: card)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: CardDetailView(card: card)) {
                cardRowContent(card: card)
            }
        }
    }

    private func cardRowContent(card: Card) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Front preview
            Text(card.front.isEmpty ? "Untitled card" : card.front)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Details subtitle
            HStack(spacing: 8) {
                if let deck = card.deck {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                        Text(deck.name)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(card.dueDate.relativeDescription)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer()

                // State badge
                Text(card.state.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor(card.state).opacity(0.15))
                    .foregroundStyle(stateColor(card.state))
                    .clipShape(Capsule())

                if card.isSuspended {
                    Text("Suspended")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Batch Action Bar

    @ViewBuilder
    private func batchActionBar(viewModel: BrowseViewModel) -> some View {
        HStack {
            // Suspend / Unsuspend
            Button {
                viewModel.suspendCards(viewModel.selectedCards)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                    Text("Suspend")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)

            // Tag
            Button {
                showAddTagAlert = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "tag.fill")
                        .font(.title3)
                    Text("Tag")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)

            // Move
            Button {
                showMoveDeckSheet = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                    Text("Move")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)

            // Delete
            Button(role: .destructive) {
                showDeleteBatchAlert = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                    Text("Delete")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color(uiColor: .separator)),
            alignment: .top
        )
    }

    // MARK: - Move Deck Sheet

    private func moveDeckSheet(viewModel: BrowseViewModel) -> some View {
        NavigationStack {
            List(decks, id: \.id) { deck in
                Button {
                    viewModel.moveCards(viewModel.selectedCards, to: deck)
                    showMoveDeckSheet = false
                } label: {
                    HStack {
                        Label(deck.name, systemImage: "folder.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(deck.cards.count) cards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Move to Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showMoveDeckSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Empty State View

    @ViewBuilder
    private func emptyStateView(viewModel: BrowseViewModel) -> some View {
        if !viewModel.searchText.isEmpty {
            ContentUnavailableView(
                "No Cards Found",
                systemImage: "magnifyingglass",
                description: Text("No cards matched '\(viewModel.searchText)'.")
            )
        } else if viewModel.selectedDeck != nil || viewModel.selectedState != nil || viewModel.selectedTag != nil {
            ContentUnavailableView(
                "No Matching Cards",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try clearing or broadening your filters.")
            )
        } else {
            ContentUnavailableView(
                "No Cards",
                systemImage: "rectangle.stack",
                description: Text("Cards you create will appear here.")
            )
        }
    }

    // MARK: - Toolbar Items

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 12) {
                if let vm = viewModel {
                    Menu {
                        Picker("Sort By", selection: Bindable(vm).sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Text(order.displayName).tag(order)
                            }
                        }

                        Divider()

                        Button {
                            vm.sortAscending.toggle()
                        } label: {
                            Label(
                                vm.sortAscending ? "Ascending Order" : "Descending Order",
                                systemImage: vm.sortAscending ? "arrow.up" : "arrow.down"
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                
                Button {
                    showHierarchicalTagsSheet = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundColor(.blue)
                }
                .accessibilityLabel("Hierarchical Tags Explorer")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(isSelectionMode ? "Done" : "Select") {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    viewModel?.selectedCards.removeAll()
                }
            }
            .fontWeight(isSelectionMode ? .bold : .regular)
        }
    }

    // MARK: - Helpers

    private func stateColor(_ state: CardState) -> Color {
        switch state {
        case .new: return .blue
        case .learning: return .orange
        case .review: return .green
        case .relearning: return .red
        }
    }
}
