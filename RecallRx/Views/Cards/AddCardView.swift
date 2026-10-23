import SwiftUI
import SwiftData

struct AddCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var defaultDeck: Deck?

    @State private var viewModel: CardEditorViewModel?
    @State private var showAddedConfirmation = false
    @State private var showingImageOcclusionCreator = false
    @State private var showDiscardConfirmation = false
    @State private var showSaveError = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    Form {
                        CardDraftFields(viewModel: vm)
                        Section {
                            Button("Save and Add Another", systemImage: "plus.circle") {
                                saveAndAddAnother(viewModel: vm)
                            }
                            .frame(minHeight: 44)
                            .disabled(!vm.isValid)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.canvas)
                } else {
                    ProgressView("Preparing a new card…")
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancelAdding)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Image Occlusion", systemImage: "photo.badge.plus") {
                        showingImageOcclusionCreator = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveCard)
                        .bold()
                        .disabled(viewModel?.isValid != true)
                }
            }
            .sheet(isPresented: $showingImageOcclusionCreator) {
                ImageOcclusionCreatorView(defaultDeck: defaultDeck ?? viewModel?.selectedDeck)
            }
            .task {
                if viewModel == nil {
                    viewModel = CardEditorViewModel(modelContext: modelContext, deck: defaultDeck, card: nil)
                } else {
                    viewModel?.fetchDecks()
                    if viewModel?.selectedDeck == nil {
                        viewModel?.selectedDeck = viewModel?.availableDecks.first
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showAddedConfirmation {
                    Label("Card saved. Ready for your next one.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.accent)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface)
                        .accessibilityElement(children: .combine)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showAddedConfirmation)
            .task(id: showAddedConfirmation) {
                guard showAddedConfirmation else { return }
                do {
                    try await Task.sleep(for: .seconds(3))
                    showAddedConfirmation = false
                } catch { }
            }
            .interactiveDismissDisabled(isPresented && hasDraft)
            .confirmationDialog("Discard this draft?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Draft", role: .destructive) { dismiss() }
                Button("Keep Writing", role: .cancel) { }
            }
            .alert("Couldn't save card", isPresented: $showSaveError) {
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Your draft is still here. Try saving again.")
            }
        }
    }

    private var hasDraft: Bool {
        guard let vm = viewModel else { return false }
        return !vm.front.isEmpty || !vm.back.isEmpty || !vm.tags.isEmpty || !vm.tagInput.isEmpty
            || !vm.extra.isEmpty || !vm.firstAid.isEmpty || !vm.sketchy.isEmpty
            || !vm.pathoma.isEmpty || !vm.clinicalPearls.isEmpty
    }

    private func cancelAdding() {
        if hasDraft { showDiscardConfirmation = true } else { dismiss() }
    }

    private func saveCard() {
        guard let vm = viewModel else { return }
        if isPresented {
            vm.addTag()
            if vm.save() { dismiss() } else { showSaveError = true }
        } else {
            saveAndAddAnother(viewModel: vm)
        }
    }

    private func saveAndAddAnother(viewModel: CardEditorViewModel) {
        viewModel.addTag()
        guard viewModel.save() else {
            showSaveError = true
            return
        }
        viewModel.front = ""
        viewModel.back = ""
        viewModel.tags.removeAll()
        viewModel.tagInput = ""
        viewModel.clozeIndex = 1
        viewModel.extra = ""
        viewModel.firstAid = ""
        viewModel.sketchy = ""
        viewModel.pathoma = ""
        viewModel.clinicalPearls = ""
        showAddedConfirmation = true
    }
}
