import SwiftUI
import SwiftData

struct AddCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var defaultDeck: Deck?

    @State private var viewModel: CardEditorViewModel?
    @State private var showAddedToast: Bool = false
    @State private var toastMessage: String = "Card added successfully!"
    @State private var showingImageOcclusionCreator: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    contentForm(viewModel: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        showingImageOcclusionCreator = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.subheadline)
                    }
                    .accessibilityLabel("Create Image Occlusion")
                    
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(viewModel?.isValid != true)
                }
            }
            .sheet(isPresented: $showingImageOcclusionCreator) {
                ImageOcclusionCreatorView(defaultDeck: defaultDeck ?? viewModel?.selectedDeck)
            }
            .task {
                if viewModel == nil {
                    viewModel = CardEditorViewModel(
                        modelContext: modelContext,
                        deck: defaultDeck,
                        card: nil
                    )
                }
            }
            .overlay(alignment: .top) {
                if showAddedToast {
                    toastBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showAddedToast)
        }
    }

    // MARK: - Main Form

    @ViewBuilder
    private func contentForm(viewModel: CardEditorViewModel) -> some View {
        Form {
            // Deck & Note Type Section
            Section("Configuration") {
                deckPicker(viewModel: viewModel)
                noteTypePicker(viewModel: viewModel)
            }

            // Front / Question Section
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
                        Text("Tap '{{c\(viewModel.clozeIndex)::}}' to add a cloze deletion for hidden text.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(viewModel.selectedNoteType == .cloze ? "Cloze Text" : "Front")
            }

            // Back / Answer Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.selectedNoteType == .cloze ? "Extra / Back Notes (Optional)" : "Back")
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

            // High-Yield Medical Resources (USMLE Step 1 & 2)
            Section {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Extra Explanation", systemImage: "doc.text.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.indigo)
                            TextField("General board explanation...", text: Bindable(viewModel).extra, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Outline", systemImage: "cross.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.blue)
                            TextField("Content outline, table, or mnemonic", text: Bindable(viewModel).firstAid, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Visual", systemImage: "paintpalette.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                            TextField("A visual hook in your own words", text: Bindable(viewModel).sketchy, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Pathology", systemImage: "microscope.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.purple)
                            TextField("Pathology note", text: Bindable(viewModel).pathoma, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Clinical Pearls / Missed Questions", systemImage: "lightbulb.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.yellow)
                            TextField("Why this was missed, question trap...", text: Bindable(viewModel).clinicalPearls, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 6)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cross.case.fill")
                            .foregroundColor(.blue)
                        Text("High-Yield Medical Resources")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            } header: {
                Text("Step 1 & 2 Resources (Optional)")
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

            // Preview Section Toggle
            Section {
                Toggle("Show Card Preview", isOn: Bindable(viewModel).showPreview)

                if viewModel.showPreview {
                    cardPreviewView(viewModel: viewModel)
                }
            } header: {
                Text("Preview")
            }

            // Action Buttons Section
            Section {
                Button {
                    saveAndAddAnother(viewModel: viewModel)
                } label: {
                    HStack {
                        Spacer()
                        Label("Save and Add Another", systemImage: "plus.circle")
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
                .disabled(!viewModel.isValid)

                Button {
                    saveAndDismiss()
                } label: {
                    HStack {
                        Spacer()
                        Label("Save Card", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!viewModel.isValid)
            }
        }
    }

    // MARK: - Form Components

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
    private func cardPreviewView(viewModel: CardEditorViewModel) -> some View {
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

    private var toastBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text(toastMessage)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func saveAndDismiss() {
        guard let vm = viewModel else { return }
        if vm.save() {
            dismiss()
        }
    }

    private func saveAndAddAnother(viewModel: CardEditorViewModel) {
        guard viewModel.save() else { return }

        // Clear the card content fields while keeping the deck and note type
        viewModel.front = ""
        viewModel.back = ""
        viewModel.tags.removeAll()
        viewModel.tagInput = ""
        viewModel.clozeIndex = 1

        toastMessage = "Card added! Form cleared for next card."
        withAnimation {
            showAddedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showAddedToast = false
            }
        }
    }
}
