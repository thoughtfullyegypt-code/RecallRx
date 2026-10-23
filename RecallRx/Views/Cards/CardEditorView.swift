import SwiftUI
import SwiftData

struct CardEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var card: Card?
    var defaultDeck: Deck?

    @State private var viewModel: CardEditorViewModel?
    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showSaveError = false

    init(card: Card? = nil, defaultDeck: Deck? = nil) {
        self.card = card
        self.defaultDeck = defaultDeck
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    Form {
                        CardDraftFields(viewModel: vm)
                        if vm.isEditing {
                            Section {
                                Button("Delete Card", systemImage: "trash", role: .destructive) {
                                    showDeleteConfirmation = true
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.canvas)
                } else {
                    ProgressView("Preparing editor…")
                }
            }
            .navigationTitle(viewModel?.isEditing == true ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancelEditing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveAndDismiss)
                        .bold()
                        .disabled(viewModel?.isValid != true)
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = CardEditorViewModel(modelContext: modelContext, deck: defaultDeck, card: card)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog("Discard your changes?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .alert("Delete card?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deleteCurrentCard)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes the card and its review history. This cannot be undone.")
            }
            .alert("Couldn't save card", isPresented: $showSaveError) {
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Your draft is still here. Try saving again.")
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let vm = viewModel else { return false }
        if let card {
            return !vm.tagInput.isEmpty || vm.front != card.front || vm.back != card.back || vm.tags != card.tags
                || vm.selectedDeck?.id != card.deck?.id || vm.selectedNoteType != card.noteType
                || vm.extra != card.extra || vm.firstAid != card.firstAid || vm.sketchy != card.sketchy
                || vm.pathoma != card.pathoma || vm.clinicalPearls != card.clinicalPearls
        }
        return !vm.front.isEmpty || !vm.back.isEmpty || !vm.tags.isEmpty || !vm.tagInput.isEmpty
            || !vm.extra.isEmpty || !vm.firstAid.isEmpty || !vm.sketchy.isEmpty
            || !vm.pathoma.isEmpty || !vm.clinicalPearls.isEmpty
    }

    private func cancelEditing() {
        if hasUnsavedChanges { showDiscardConfirmation = true } else { dismiss() }
    }

    private func saveAndDismiss() {
        guard let vm = viewModel else { return }
        vm.addTag()
        if vm.save() { dismiss() } else { showSaveError = true }
    }

    private func deleteCurrentCard() {
        if let card = card ?? viewModel?.editingCard {
            modelContext.delete(card)
            try? modelContext.save()
        }
        dismiss()
    }
}
