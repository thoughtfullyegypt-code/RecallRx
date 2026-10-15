import SwiftUI
import SwiftData

struct ImageOcclusionCreatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Deck.name) private var decks: [Deck]
    
    @State private var selectedDeck: Deck?
    @State private var selectedDiagramId: String = "circle_of_willis"
    @State private var masks: [ImageOcclusionMask] = []
    @State private var selectedMaskId: Int?
    @State private var mode: ImageOcclusionMode = .hideAllGuessOne
    @State private var clinicalNotes: String = ""
    @State private var editingLabel: String = ""
    @State private var showLabelEditor: Bool = false
    @State private var generatedCount: Int = 0
    @State private var showSuccessAlert: Bool = false
    
    private var selectedDiagram: MedicalDiagramDefinition {
        MedicalDiagramRegistry.diagrams.first(where: { $0.id == selectedDiagramId }) ?? MedicalDiagramRegistry.diagrams[0]
    }
    
    init(defaultDeck: Deck? = nil) {
        self._selectedDeck = State(initialValue: defaultDeck)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Target Deck & Diagram Selection
                Section("Setup") {
                    Picker("Target Deck", selection: $selectedDeck) {
                        Text("Select a Deck").tag(nil as Deck?)
                        ForEach(decks, id: \.id) { deck in
                            Text(deck.name).tag(deck as Deck?)
                        }
                    }
                    
                    Picker("Diagram Template", selection: $selectedDiagramId) {
                        ForEach(MedicalDiagramRegistry.diagrams, id: \.id) { diag in
                            Text(diag.title).tag(diag.id)
                        }
                    }
                    .onChange(of: selectedDiagramId) { _, _ in
                        loadDiagramMasks()
                    }
                }
                
                // Section 2: Interactive Occlusion Canvas
                Section("Interactive Occlusion Canvas (\(masks.count) Masks)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tap a mask to edit label or structure name:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ZStack {
                            MedicalDiagramCanvasView(diagramId: selectedDiagram.id)
                                .frame(maxWidth: .infinity)
                            
                            // Masks Overlay
                            GeometryReader { geo in
                                ForEach(masks) { mask in
                                    let isSelected = selectedMaskId == mask.id
                                    
                                    Button {
                                        selectedMaskId = mask.id
                                        editingLabel = mask.label
                                        showLabelEditor = true
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? Color.orange.opacity(0.85) : Color.blue.opacity(0.75))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(Color.white, lineWidth: 1.5)
                                                )
                                                .shadow(color: Color.black.opacity(0.15), radius: 3)
                                            
                                            Text("[\(mask.id)]")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .frame(
                                            width: max(30, geo.size.width * mask.width),
                                            height: max(20, geo.size.height * mask.height)
                                        )
                                        .position(
                                            x: geo.size.width * (mask.x + mask.width / 2.0),
                                            y: geo.size.height * (mask.y + mask.height / 2.0)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(height: 240)
                        
                        HStack {
                            Button {
                                addNewMask()
                            } label: {
                                Label("Add Mask Box", systemImage: "plus.rectangle.fill")
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            
                            Spacer()
                            
                            Picker("Study Mode", selection: $mode) {
                                Text("Hide All, Guess 1").tag(ImageOcclusionMode.hideAllGuessOne)
                                Text("Hide 1, Guess 1").tag(ImageOcclusionMode.hideOneGuessOne)
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Section 3: Masks List & Structure Answers
                Section("Masked Structures & Answers") {
                    if masks.isEmpty {
                        Text("No masks created. Tap 'Add Mask Box' to place an occlusion.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach($masks) { $mask in
                            HStack {
                                Text("[\(mask.id)]")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                                
                                TextField("Structure name", text: $mask.label)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Button(role: .destructive) {
                                    deleteMask(id: mask.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Section 4: Clinical Notes & USMLE Correlation
                Section("Clinical Pearls & USMLE Notes") {
                    TextField("e.g. Aneurysm causes CN III palsy or stroke syndrome...", text: $clinicalNotes, axis: .vertical)
                        .lineLimit(3...5)
                }
                
                // Section 5: Generation Action
                Section {
                    Button {
                        generateCards()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "sparkles")
                            Text("Generate \(masks.count) Image Occlusion Cards")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(selectedDeck == nil || masks.isEmpty)
                }
            }
            .navigationTitle("Image Occlusion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if selectedDeck == nil {
                    selectedDeck = decks.first
                }
                loadDiagramMasks()
            }
            .alert("Edit Mask Label", isPresented: $showLabelEditor) {
                TextField("Structure Label", text: $editingLabel)
                Button("Save") {
                    if let id = selectedMaskId, let idx = masks.firstIndex(where: { $0.id == id }) {
                        masks[idx].label = editingLabel
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Cards Created!", isPresented: $showSuccessAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Successfully generated \(generatedCount) Image Occlusion cards in '\(selectedDeck?.name ?? "Deck")'!")
            }
        }
    }
    
    // MARK: - Actions
    private func loadDiagramMasks() {
        masks = selectedDiagram.defaultMasks
        clinicalNotes = selectedDiagram.description
    }
    
    private func addNewMask() {
        let newId = (masks.map(\.id).max() ?? 0) + 1
        let newMask = ImageOcclusionMask(
            id: newId,
            label: "Structure #\(newId)",
            x: 0.40,
            y: 0.40,
            width: 0.25,
            height: 0.08
        )
        masks.append(newMask)
        selectedMaskId = newId
        editingLabel = newMask.label
        showLabelEditor = true
    }
    
    private func deleteMask(id: Int) {
        masks.removeAll { $0.id == id }
    }
    
    private func generateCards() {
        guard let deck = selectedDeck, !masks.isEmpty else { return }
        
        var count = 0
        for mask in masks {
            let payload = ImageOcclusionPayload(
                diagramId: selectedDiagram.id,
                title: selectedDiagram.title,
                masks: masks,
                activeMaskId: mask.id,
                mode: mode,
                clinicalNotes: clinicalNotes
            )
            
            let json = payload.toJSON()
            let answer = mask.label
            
            let card = Card(
                front: json,
                back: answer,
                deck: deck,
                tags: ["#ImageOcclusion", "#\(selectedDiagram.category)", "#\(selectedDiagram.id)"],
                noteTypeRaw: NoteType.imageOcclusion.rawValue,
                clinicalPearls: clinicalNotes
            )
            
            modelContext.insert(card)
            count += 1
        }
        
        deck.modifiedAt = .now
        try? modelContext.save()
        generatedCount = count
        showSuccessAlert = true
    }
}
