import SwiftUI
import SwiftData

struct CardEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var card: Card?
    var defaultDeck: Deck?

    @State private var viewModel: CardEditorViewModel?
    @State private var showDeleteConfirmation: Bool = false

    init(card: Card? = nil, defaultDeck: Deck? = nil) {
        self.card = card
        self.defaultDeck = defaultDeck
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    editorForm(viewModel: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(viewModel?.isEditing == true ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel?.isValid != true)
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = CardEditorViewModel(
                        modelContext: modelContext,
                        deck: defaultDeck,
                        card: card
                    )
                }
            }
            .alert("Delete Card", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteCurrentCard()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this card? This action cannot be undone.")
            }
        }
    }

    // MARK: - Editor Form

    @ViewBuilder
    private func editorForm(viewModel: CardEditorViewModel) -> some View {
        Form {
            // Deck & Note Type
            Section("Card Settings") {
                deckPicker(viewModel: viewModel)
                noteTypePicker(viewModel: viewModel)
            }

            // Front / Question
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(viewModel.selectedNoteType == .cloze ? "Text with Cloze" : "Front")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if viewModel.selectedNoteType == .cloze {
                            Button {
                                viewModel.insertCloze()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "curlybraces")
                                    Text("{{c\(viewModel.clozeIndex)::}}")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if viewModel.front.isEmpty {
                            Text(viewModel.selectedNoteType == .cloze
                                 ? "e.g. The capital of France is {{c1::Paris}}."
                                 : "Enter the prompt or question...")
                                .font(.body)
                                .foregroundStyle(Color(uiColor: .placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: Bindable(viewModel).front)
                            .font(.body)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                    }

                    if viewModel.selectedNoteType == .cloze {
                        Text("Use {{c1::hidden text}} syntax for cloze deletions.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(viewModel.selectedNoteType == .cloze ? "Cloze Text" : "Front")
            }

            // Back / Answer
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.selectedNoteType == .cloze ? "Extra Notes (revealed on back)" : "Back")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        if viewModel.back.isEmpty {
                            Text(viewModel.selectedNoteType == .cloze
                                 ? "Additional explanation shown after answering..."
                                 : "Enter the answer or explanation...")
                                .font(.body)
                                .foregroundStyle(Color(uiColor: .placeholderText))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: Bindable(viewModel).back)
                            .font(.body)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                    }
                }
            } header: {
                Text(viewModel.selectedNoteType == .cloze ? "Additional Notes" : "Back")
            }

            // Tags Section
            Section("Tags") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)

                        TextField("Add new tag...", text: Bindable(viewModel).tagInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                viewModel.addTag()
                            }

                        Button {
                            viewModel.addTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(viewModel.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !viewModel.tags.isEmpty {
                        tagChipsFlow(viewModel: viewModel)
                    }
                }
                .padding(.vertical, 4)
            }

            // Preview Section
            Section {
                Toggle("Show Card Preview", isOn: Bindable(viewModel).showPreview)

                if viewModel.showPreview {
                    previewSection(viewModel: viewModel)
                }
            } header: {
                Text("Preview")
            }

            // Delete Card Option (Editing Only)
            if viewModel.isEditing {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Card", systemImage: "trash")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Component Views

    @ViewBuilder
    private func deckPicker(viewModel: CardEditorViewModel) -> some View {
        HStack {
            Label("Deck", systemImage: "folder.fill")
                .foregroundStyle(.primary)

            Spacer()

            if viewModel.availableDecks.isEmpty {
                Text("No decks available")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Deck", selection: Bindable(viewModel).selectedDeck) {
                    ForEach(viewModel.availableDecks, id: \.id) { deck in
                        Text(deck.name)
                            .tag(Optional(deck))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func noteTypePicker(viewModel: CardEditorViewModel) -> some View {
        HStack {
            Label("Type", systemImage: viewModel.selectedNoteType.iconName)
                .foregroundStyle(.primary)

            Spacer()

            Picker("Type", selection: Bindable(viewModel).selectedNoteType) {
                ForEach(NoteType.allCases) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func tagChipsFlow(viewModel: CardEditorViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.caption)
                            .fontWeight(.medium)

                        Button {
                            viewModel.removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func previewSection(viewModel: CardEditorViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Front Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("FRONT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(viewModel.selectedNoteType == .cloze
                     ? viewModel.clozeQuestionPreview
                     : (viewModel.front.isEmpty ? "Question preview..." : viewModel.front))
                    .font(.body)
                    .foregroundStyle(viewModel.front.isEmpty ? .secondary : .primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Back Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("BACK")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(viewModel.selectedNoteType == .cloze
                     ? viewModel.clozeAnswerPreview
                     : (viewModel.back.isEmpty ? "Answer preview..." : viewModel.back))
                    .font(.body)
                    .foregroundStyle(viewModel.back.isEmpty ? .secondary : .primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if viewModel.selectedNoteType == .cloze && !viewModel.back.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NOTES")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Text(viewModel.back)
                            .font(.callout)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        guard let vm = viewModel else { return }
        if vm.save() {
            dismiss()
        }
    }

    private func deleteCurrentCard() {
        if let card = card ?? viewModel?.editingCard {
            modelContext.delete(card)
            try? modelContext.save()
        }
        dismiss()
    }
}
