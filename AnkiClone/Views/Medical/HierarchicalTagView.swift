import SwiftUI
import SwiftData

struct HierarchicalTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel: HierarchicalTagViewModel?
    @State private var createdCramDeck: Deck? = nil
    @State private var navigateToStudy: Bool = false
    @State private var selectedCardNode: TagTreeNode? = nil
    
    init() {}
    
    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    contentView(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Hierarchical Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel?.fetchAndBuildTree()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = HierarchicalTagViewModel(modelContext: modelContext)
                }
            }
            .navigationDestination(isPresented: $navigateToStudy) {
                if let deck = createdCramDeck {
                    StudyView(deck: deck)
                }
            }
            .sheet(item: $selectedCardNode) { node in
                TagCardsListView(node: node, viewModel: viewModel)
            }
        }
    }
    
    @ViewBuilder
    private func contentView(vm: HierarchicalTagViewModel) -> some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search medical topics (e.g. FirstAid, Pathoma)...", text: Bindable(vm).searchText)
                    .textFieldStyle(.plain)
                
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Notification Banner
            if let msg = vm.lastActionMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.footnote)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
            }
            
            // Tree List
            if vm.filteredRoots.isEmpty {
                ContentUnavailableView {
                    Label("No Tags Found", systemImage: "tag.slash")
                } description: {
                    Text("No hierarchical tags found. Cards with '::' delimiters (e.g. #FirstAid::Cardio) will appear here as a folder tree.")
                }
            } else {
                List {
                    ForEach(vm.filteredRoots) { root in
                        TagTreeNodeRow(
                            node: root,
                            level: 0,
                            expandedNodeIDs: Bindable(vm).expandedNodeIDs,
                            onUnsuspend: { node in
                                vm.unsuspendNode(node)
                            },
                            onSuspend: { node in
                                vm.suspendNode(node)
                            },
                            onCram: { node in
                                if let deck = vm.createCramDeck(for: node) {
                                    createdCramDeck = deck
                                    navigateToStudy = true
                                }
                            },
                            onViewCards: { node in
                                selectedCardNode = node
                            }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - Recursive Tree Row View
private struct TagTreeNodeRow: View {
    let node: TagTreeNode
    let level: Int
    @Binding var expandedNodeIDs: Set<String>
    let onUnsuspend: (TagTreeNode) -> Void
    let onSuspend: (TagTreeNode) -> Void
    let onCram: (TagTreeNode) -> Void
    let onViewCards: (TagTreeNode) -> Void
    
    private var isExpanded: Bool {
        expandedNodeIDs.contains(node.id)
    }
    
    private var hasChildren: Bool {
        !node.children.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Indentation
                if level > 0 {
                    Spacer()
                        .frame(width: CGFloat(level) * 16)
                }
                
                // Chevron
                if hasChildren {
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            if isExpanded {
                                expandedNodeIDs.remove(node.id)
                            } else {
                                expandedNodeIDs.insert(node.id)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 18)
                }
                
                // Folder / Tag icon
                Image(systemName: hasChildren ? (isExpanded ? "folder.fill" : "folder") : "tag.fill")
                    .foregroundColor(iconColor)
                    .font(.footnote)
                
                // Name
                Text(node.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Badges
                HStack(spacing: 4) {
                    Text("\(node.totalCardsCount)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(5)
                    
                    if node.suspendedCardsCount > 0 {
                        Text("\(node.suspendedCardsCount)s")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(5)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    onViewCards(node)
                } label: {
                    Label("View \(node.totalCardsCount) Cards", systemImage: "rectangle.stack")
                }
                
                Button {
                    onUnsuspend(node)
                } label: {
                    Label("Unsuspend All in Branch (\(node.suspendedCardsCount))", systemImage: "bolt.fill")
                }
                
                Button {
                    onCram(node)
                } label: {
                    Label("Cram This Topic", systemImage: "play.fill")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onSuspend(node)
                } label: {
                    Label("Suspend All in Branch", systemImage: "pause.circle")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    onUnsuspend(node)
                } label: {
                    Label("Unsuspend", systemImage: "bolt.fill")
                }
                .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button {
                    onCram(node)
                } label: {
                    Label("Cram", systemImage: "play.fill")
                }
                .tint(.blue)
            }
            
            // Expanded Children
            if isExpanded && hasChildren {
                ForEach(node.children) { child in
                    TagTreeNodeRow(
                        node: child,
                        level: level + 1,
                        expandedNodeIDs: $expandedNodeIDs,
                        onUnsuspend: onUnsuspend,
                        onSuspend: onSuspend,
                        onCram: onCram,
                        onViewCards: onViewCards
                    )
                }
            }
        }
    }
    
    private var iconColor: Color {
        let nameLower = node.name.lowercased()
        if nameLower.contains("firstaid") {
            return .blue
        } else if nameLower.contains("pathoma") {
            return .purple
        } else if nameLower.contains("sketchy") || nameLower.contains("pixorize") {
            return .orange
        } else if nameLower.contains("uworld") || nameLower.contains("amboss") {
            return .red
        }
        return .accentColor
    }
}

// MARK: - Tag Cards List Sheet
private struct TagCardsListView: View {
    let node: TagTreeNode
    let viewModel: HierarchicalTagViewModel?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            let cards = viewModel?.getCards(for: node) ?? []
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(node.fullPath)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text("\(cards.count) cards total (\(node.suspendedCardsCount) suspended)")
                                .font(.caption.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                
                Section("Cards") {
                    ForEach(cards) { card in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.front.truncated50)
                                    .font(.subheadline)
                                Text(card.back.truncated50)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: card.isSuspended ? "pause.circle.fill" : "play.circle.fill")
                                .foregroundColor(card.isSuspended ? .orange : .green)
                        }
                    }
                }
            }
            .navigationTitle(node.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
