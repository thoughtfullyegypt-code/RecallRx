import SwiftUI

struct DeckRowHierarchyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        let isExpanded = isSearching || expandedDeckIDs.contains(deck.id)
        let dueCounts = vm.getDueCount(for: deck)

        HStack(spacing: 4) {
            if level > 0 {
                Spacer().frame(width: CGFloat(min(level, 3)) * 12)
            }

            if !subdecks.isEmpty {
                Button(action: toggleExpanded) {
                    Label(isExpanded ? "Collapse subdecks" : "Expand subdecks",
                          systemImage: isExpanded ? "chevron.down" : "chevron.right")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.bold())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(deck.displayName) subdecks")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .disabled(isSearching)
            }

            NavigationLink(destination: DeckDetailView(deck: deck)) {
                DeckRowView(
                    deck: deck,
                    newCount: dueCounts.new,
                    learningCount: dueCounts.learning,
                    reviewCount: dueCounts.review
                )
            }
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
    private var isSearching: Bool {
        !vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleExpanded() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            if expandedDeckIDs.contains(deck.id) {
                expandedDeckIDs.remove(deck.id)
            } else {
                expandedDeckIDs.insert(deck.id)
            }
        }
    }

}
