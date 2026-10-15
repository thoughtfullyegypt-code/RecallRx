import SwiftUI
import SwiftData

struct QBankUnsuspendView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel: QBankViewModel?
    @State private var showingCramAlert: Bool = false
    @State private var cramDeckName: String = "UWorld Incorrects Cram"
    @State private var showingTagAlert: Bool = false
    @State private var newTagName: String = "UWorld_Incorrects"
    @State private var expandedQIDs: Set<String> = []
    @State private var createdCramDeck: Deck? = nil
    @State private var navigateToStudy: Bool = false
    
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
            .navigationTitle("QBank Fast-Unsuspend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if viewModel == nil {
                    let vm = QBankViewModel(modelContext: modelContext)
                    self.viewModel = vm
                }
            }
            .alert("Create Cram Deck", isPresented: $showingCramAlert) {
                TextField("Deck Name", text: $cramDeckName)
                Button("Create and Start", role: .none) {
                    if let deck = viewModel?.createCramDeck(name: cramDeckName) {
                        createdCramDeck = deck
                        navigateToStudy = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will move the \(viewModel?.totalMatchedCount ?? 0) matched cards into a temporary cram deck and make them due for immediate review.")
            }
            .alert("Add Tag to Matched Cards", isPresented: $showingTagAlert) {
                TextField("Tag Name", text: $newTagName)
                Button("Apply Tag") {
                    viewModel?.addTagToAll(tag: newTagName)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Add this tag to all \(viewModel?.totalMatchedCount ?? 0) matched cards.")
            }
            .navigationDestination(isPresented: $navigateToStudy) {
                if let deck = createdCramDeck {
                    StudyView(deck: deck)
                }
            }
        }
    }
    
    @ViewBuilder
    private func contentView(vm: QBankViewModel) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                // Info Header Card
                headerBanner
                
                // QBank Source & Deck Selector
                sourceAndDeckCard(vm: vm)
                
                // Input Section
                inputCard(vm: vm)
                
                // Action Banner (if matches found)
                if !vm.matchResults.isEmpty {
                    resultsSummaryCard(vm: vm)
                    resultsList(vm: vm)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "cross.case.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Step 1 & Step 2 QBank Bridge")
                    .font(.headline)
                Text("Paste missed question IDs. Matching cards are unsuspended so you can review them.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Source & Deck Selection
    @ViewBuilder
    private func sourceAndDeckCard(vm: QBankViewModel) -> some View {
        VStack(spacing: 12) {
            Picker("QBank Source", selection: Binding(
                get: { vm.selectedSource },
                set: { vm.selectedSource = $0; vm.searchQIDs() }
            )) {
                ForEach(QBankSource.allCases) { source in
                    Label(source.rawValue, systemImage: source.iconName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.orange)
                Text("Search In:")
                    .font(.subheadline)
                Spacer()
                Menu {
                    Button("All Decks") {
                        vm.selectedDeck = nil
                        vm.searchQIDs()
                    }
                    Divider()
                    ForEach(vm.availableDecks) { deck in
                        Button(deck.displayName) {
                            vm.selectedDeck = deck
                            vm.searchQIDs()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(vm.selectedDeck?.displayName ?? "All Decks")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Input Section
    @ViewBuilder
    private func inputCard(vm: QBankViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Question IDs (QIDs)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                
                Button("Paste") {
                    if let string = UIPasteboard.general.string {
                        vm.rawInput = string
                        vm.searchQIDs()
                    }
                }
                .font(.caption.weight(.medium))
                
                Button("Sample") {
                    vm.loadSampleQIDs()
                }
                .font(.caption.weight(.medium))
                
                if !vm.rawInput.isEmpty {
                    Button("Clear") {
                        vm.clear()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            
            TextEditor(text: Binding(
                get: { vm.rawInput },
                set: { vm.rawInput = $0; vm.searchQIDs() }
            ))
            .frame(minHeight: 80)
            .padding(8)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(8)
            .overlay(
                Group {
                    if vm.rawInput.isEmpty {
                        Text("Paste QIDs separated by commas, spaces, or lines (e.g. 1024, 2048, 15302)...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.leading, 14)
                            .padding(.top, 14)
                            .allowsHitTesting(false)
                    }
                },
                alignment: .topLeading
            )
            
            if !vm.parsedQIDs.isEmpty {
                HStack {
                    Image(systemName: "number.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("\(vm.parsedQIDs.count) QIDs recognized")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Search Now") {
                        vm.searchQIDs()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Results Summary & Action Bar
    @ViewBuilder
    private func resultsSummaryCard(vm: QBankViewModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found \(vm.totalMatchedCount) Cards")
                        .font(.headline)
                    Text("\(vm.totalSuspendedMatchedCount) currently suspended")
                        .font(.caption)
                        .foregroundColor(vm.totalSuspendedMatchedCount > 0 ? .orange : .green)
                }
                Spacer()
            }
            
            if let msg = vm.lastActionMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.footnote)
                    Spacer()
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Primary Action Buttons
            HStack(spacing: 10) {
                // Unsuspend All Button
                Button {
                    vm.unsuspendAll()
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Unsuspend All (\(vm.totalSuspendedMatchedCount))")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(vm.totalSuspendedMatchedCount == 0)
                
                // Cram Button
                Button {
                    showingCramAlert = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Cram")
                            .bold()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(vm.totalMatchedCount == 0)
            }
            
            // Secondary Options
            HStack(spacing: 12) {
                Button {
                    showingTagAlert = true
                } label: {
                    Label("Tag Matched", systemImage: "tag.fill")
                        .font(.footnote)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    vm.suspendAll()
                } label: {
                    Label("Suspend All", systemImage: "pause.circle")
                        .font(.footnote)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Results List
    @ViewBuilder
    private func resultsList(vm: QBankViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Matched QIDs Breakdown")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            ForEach(vm.matchResults) { result in
                qidResultRow(result: result, vm: vm)
            }
        }
    }
    
    @ViewBuilder
    private func qidResultRow(result: QIDMatchResult, vm: QBankViewModel) -> some View {
        let isExpanded = expandedQIDs.contains(result.qid)
        
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded {
                    expandedQIDs.remove(result.qid)
                } else {
                    expandedQIDs.insert(result.qid)
                }
            } label: {
                HStack {
                    Image(systemName: result.isFound ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .foregroundColor(result.isFound ? .green : .secondary)
                    
                    Text("QID \(result.qid)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if result.isFound {
                        Text("\(result.cards.count) cards")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        
                        if result.suspendedCount > 0 {
                            Text("\(result.suspendedCount) susp")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    } else {
                        Text("Not in deck")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded && result.isFound {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(result.cards) { card in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.front.truncated50)
                                    .font(.footnote)
                                    .lineLimit(2)
                                
                                if let deckName = card.deck?.displayName {
                                    Text(deckName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            
                            Button {
                                card.isSuspended.toggle()
                                card.modifiedAt = Date()
                                try? modelContext.save()
                                vm.searchQIDs()
                            } label: {
                                Image(systemName: card.isSuspended ? "pause.circle.fill" : "play.circle.fill")
                                    .foregroundColor(card.isSuspended ? .orange : .green)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
