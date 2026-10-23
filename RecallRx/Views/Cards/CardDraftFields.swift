import SwiftUI

/// The same writing, tagging, and preview controls are used when creating and editing a card.
struct CardDraftFields: View {
    @Bindable var viewModel: CardEditorViewModel

    var body: some View {
        Section {
            Text(viewModel.isEditing ? "Make each review a little clearer." : "One question. One clear answer.")
                .font(.headline)
            Text("Keep the prompt focused so you can recall the answer before revealing it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

        Section {
            if viewModel.availableDecks.isEmpty {
                Label("Create a deck first", systemImage: "folder.badge.plus")
                Text("Go to Decks and add a deck, then return here to save your card.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Deck", selection: $viewModel.selectedDeck) {
                    ForEach(viewModel.availableDecks, id: \.id) { deck in
                        Text(deck.name).tag(Optional(deck))
                    }
                }
            }
            Picker("Card type", selection: $viewModel.selectedNoteType) {
                ForEach(NoteType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
        } header: {
            Text("Organize")
        } footer: {
            Text(viewModel.selectedNoteType.description)
        }

        Section {
            TextField(
                viewModel.selectedNoteType == .cloze
                    ? "The mitral valve separates the {{c1::left atrium}} and left ventricle."
                    : "What would you like to remember?",
                text: $viewModel.front,
                axis: .vertical
            )
            .lineLimit(4...)
            .accessibilityLabel(viewModel.selectedNoteType == .cloze ? "Cloze text" : "Question")

            if viewModel.selectedNoteType == .cloze {
                Button("Insert Cloze \(viewModel.clozeIndex)", systemImage: "curlybraces") {
                    viewModel.insertCloze()
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text(viewModel.selectedNoteType == .cloze ? "Cloze text" : "Question")
        } footer: {
            if viewModel.selectedNoteType == .cloze {
                Text("Wrap the answer in {{c1::hidden text}}. Use another number to test a different part of the same sentence.")
            }
        }

        Section {
            TextField(
                viewModel.selectedNoteType == .cloze ? "Add context or an explanation (optional)" : "Write a concise answer, then add an explanation if helpful",
                text: $viewModel.back,
                axis: .vertical
            )
            .lineLimit(4...)
            .accessibilityLabel(viewModel.selectedNoteType == .cloze ? "Additional notes" : "Answer")
        } header: {
            Text(viewModel.selectedNoteType == .cloze ? "Additional notes · optional" : "Answer")
        }

        Section {
            DisclosureGroup("Medical references · optional") {
                LabeledContent("Extra context") {
                    TextField("Explanation or source", text: $viewModel.extra, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Outline") {
                    TextField("Outline or mnemonic", text: $viewModel.firstAid, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Visual hook") {
                    TextField("Describe a visual cue", text: $viewModel.sketchy, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Pathology") {
                    TextField("Pathology note", text: $viewModel.pathoma, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Clinical pearls") {
                    TextField("Question trap or learning point", text: $viewModel.clinicalPearls, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            Text("References are shown with the answer. Verify clinical information against your source.")
        }

        Section {
            HStack {
                TextField("Add a tag", text: $viewModel.tagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(viewModel.addTag)
                Button(action: viewModel.addTag) {
                    Label("Add Tag", systemImage: "plus.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !viewModel.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.tags, id: \.self) { tag in
                            Button {
                                viewModel.removeTag(tag)
                            } label: {
                                Label(tag, systemImage: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .background(AppTheme.accent.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        } header: {
            Text("Tags · optional")
        } footer: {
            Text("Tags help you find related cards across decks.")
        }

        Section {
            Toggle("Preview card", isOn: $viewModel.showPreview)
            if viewModel.showPreview {
                CardDraftPreview(viewModel: viewModel)
            }
        }

        if !viewModel.isValid && !viewModel.availableDecks.isEmpty {
            Section {
                Label(
                    viewModel.selectedNoteType == .cloze
                        ? "Add cloze text or a question and answer to save."
                        : "Add a question and answer to save.",
                    systemImage: "info.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
    }
}
