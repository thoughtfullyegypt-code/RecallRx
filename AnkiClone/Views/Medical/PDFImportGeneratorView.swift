import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Lecture PDF & Slide Deck Card Generator Sheet with Safety Warnings & Approval Flow
struct PDFImportGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Deck.name) private var decks: [Deck]
    
    @State private var showingFilePicker: Bool = false
    @State private var selectedDeck: Deck?
    @State private var lectureTitle: String = "Cardiology Lecture"
    @State private var generatedCandidates: [GeneratedCardCandidate] = []
    @State private var isAnalyzing: Bool = false
    @State private var statusMessage: String?
    @State private var showStatusAlert: Bool = false
    
    // Card editing state
    @State private var editingCandidate: GeneratedCardCandidate?
    
    var autoLoadSample: Bool = false
    
    // Sample demo text for quick testing
    @State private var pastedNotes: String = ""
    @State private var inputMode: InputMode = .filePicker
    
    enum InputMode: String, CaseIterable {
        case filePicker = "PDF Document"
        case pasteText = "Paste Notes"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Input Source
                Section("Lecture Material Source") {
                    Picker("Input Source", selection: $inputMode) {
                        ForEach(InputMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    TextField("Lecture / Topic Name", text: $lectureTitle)
                    
                    if inputMode == .filePicker {
                        Button {
                            showingFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.viewfinder.fill")
                                    .foregroundColor(.blue)
                                Text("Select PDF Lecture Slides")
                                    .fontWeight(.medium)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Paste Lecture Notes / Outline:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $pastedNotes)
                                .frame(height: 100)
                                .font(.system(.caption, design: .monospaced))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            
                            HStack {
                                Button("Synthesize Cards") {
                                    synthesizeFromPastedNotes()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(pastedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                Button("Load Medical Sample") {
                                    loadSampleNotes()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Section 2: Destination Deck
                Section("Target Deck") {
                    Picker("Save Into", selection: $selectedDeck) {
                        Text("Create New Deck: \"\(lectureTitle)\"").tag(Optional<Deck>.none)
                        ForEach(decks) { deck in
                            Text(deck.name).tag(Optional(deck))
                        }
                    }
                }
                
                // Section 3: Generated Draft Cards Preview
                if !generatedCandidates.isEmpty {
                    Section {
                        let selectedCount = generatedCandidates.filter { $0.isSelected }.count
                        HStack {
                            Text("\(generatedCandidates.count) Draft Cards Synthesized")
                                .font(.headline)
                            Spacer()
                            Text("\(selectedCount) Approved")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        
                        ForEach($generatedCandidates) { $candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Toggle(isOn: $candidate.isSelected) {
                                        HStack(spacing: 6) {
                                            Text("Slide \(candidate.sourceSlide)")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.12))
                                                .foregroundColor(.blue)
                                                .clipShape(Capsule())
                                            
                                            Text(candidate.noteType == .cloze ? "Cloze" : "Q&A")
                                                .font(.caption2.bold())
                                                .foregroundColor(.secondary)
                                            
                                            if candidate.wasEdited {
                                                Text("Edited")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.purple.opacity(0.12))
                                                    .foregroundColor(.purple)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                                
                                // Question Text
                                Text(candidate.front.replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: ""))
                                    .font(.subheadline)
                                    .lineLimit(2)
                                
                                // Answer Text
                                Text(candidate.back.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                
                                // Safety Warning Flag if drug doses or lab values detected
                                if candidate.hasNumericalWarning {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(candidate.numericalWarningMessage ?? "⚠️ Verify against your source")
                                            .font(.caption2.bold())
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
                                }
                                
                                // Source Passage Citation
                                HStack {
                                    Text("Source: \"\(candidate.sourcePassage.prefix(50))...\"")
                                        .font(.caption2.italic())
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Edit Draft") {
                                        editingCandidate = candidate
                                    }
                                    .font(.caption2.bold())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        Button {
                            importSelectedCards()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Approve & Import \(selectedCount) Cards")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCount == 0)
                    } header: {
                        Text("Draft Cards & Source Verification")
                    } footer: {
                        Text("All cards are drafts requiring approval. Drug doses and lab values are flagged for verification against authoritative sources.")
                    }
                }
            }
            .navigationTitle("AI Card Generator (PDF)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf, .plainText]
            ) { result in
                handleFileSelection(result)
            }
            .sheet(item: $editingCandidate) { draft in
                editCandidateSheet(for: draft)
            }
            .alert("Import Status", isPresented: $showStatusAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text(statusMessage ?? "")
            }
            .onAppear {
                if autoLoadSample {
                    inputMode = .pasteText
                    loadSampleNotes()
                }
            }
        }
    }
    
    // MARK: - Draft Edit Sheet
    
    private func editCandidateSheet(for draft: GeneratedCardCandidate) -> some View {
        NavigationStack {
            Form {
                Section("Source Passage") {
                    Text(draft.sourcePassage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Question (Front)") {
                    TextField("Front", text: Binding(
                        get: { draft.front },
                        set: { newFront in
                            if let idx = generatedCandidates.firstIndex(where: { $0.id == draft.id }) {
                                generatedCandidates[idx].front = newFront
                                generatedCandidates[idx].wasEdited = true
                                PDFCardTelemetry.shared.logEdited()
                            }
                        }
                    ))
                }
                
                Section("Answer (Back)") {
                    TextField("Back", text: Binding(
                        get: { draft.back },
                        set: { newBack in
                            if let idx = generatedCandidates.firstIndex(where: { $0.id == draft.id }) {
                                generatedCandidates[idx].back = newBack
                                generatedCandidates[idx].wasEdited = true
                                PDFCardTelemetry.shared.logEdited()
                            }
                        }
                    ))
                }
            }
            .navigationTitle("Edit Draft Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        editingCandidate = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleFileSelection(_ result: Result<URL, Error>) {
        do {
            let fileURL = try result.get()
            guard fileURL.startAccessingSecurityScopedResource() else {
                statusMessage = "Could not access selected PDF file."
                showStatusAlert = true
                return
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }
            
            isAnalyzing = true
            let title = fileURL.deletingPathExtension().lastPathComponent
            lectureTitle = title
            
            let candidates = PDFCardGenerator.generateCards(from: fileURL, deckName: title)
            isAnalyzing = false
            
            if candidates.isEmpty {
                statusMessage = "No clinical text or recognizable concepts found in this PDF."
                showStatusAlert = true
            } else {
                generatedCandidates = candidates
            }
        } catch {
            statusMessage = "Error reading PDF: \(error.localizedDescription)"
            showStatusAlert = true
        }
    }
    
    private func synthesizeFromPastedNotes() {
        let candidates = PDFCardGenerator.generateCards(fromPlainText: pastedNotes, lectureName: lectureTitle)
        if candidates.isEmpty {
            statusMessage = "No medical patterns recognized in the pasted text."
            showStatusAlert = true
        } else {
            generatedCandidates = candidates
        }
    }
    
    private func loadSampleNotes() {
        pastedNotes = """
        Hypertrophic Cardiomyopathy is defined as asymmetric septal hypertrophy causing dynamic LV outflow obstruction.
        Classic triad of aortic stenosis: angina, syncope, and heart failure dyspnea.
        First-line treatment for acute pericarditis: NSAIDs (ibuprofen 800 mg TID) and colchicine 0.5 mg daily.
        Mechanism of action: Beta-blockers reduce myocardial oxygen demand by decreasing heart rate and contractility.
        Diagnosis: Transthoracic echocardiography showing systolic anterior motion of the mitral valve.
        """
        synthesizeFromPastedNotes()
    }
    
    private func importSelectedCards() {
        let toImport = generatedCandidates.filter { $0.isSelected }
        let rejectedCount = generatedCandidates.count - toImport.count
        guard !toImport.isEmpty else { return }
        
        // Target deck or create new
        let targetDeck: Deck
        if let existing = selectedDeck {
            targetDeck = existing
        } else {
            let newDeck = Deck(name: "📚 \(lectureTitle)", descriptionText: "Synthesized from \(lectureTitle)")
            modelContext.insert(newDeck)
            targetDeck = newDeck
        }
        
        var importedCount = 0
        for candidate in toImport {
            let card = Card(
                front: candidate.front,
                back: candidate.back,
                deck: targetDeck,
                tags: candidate.tags,
                noteType: candidate.noteType
            )
            card.clinicalPearls = candidate.clinicalPearl
            modelContext.insert(card)
            targetDeck.cards.append(card)
            importedCount += 1
        }
        
        // Log telemetry
        PDFCardTelemetry.shared.logApproved(count: importedCount)
        if rejectedCount > 0 {
            PDFCardTelemetry.shared.logRejected(count: rejectedCount)
        }
        
        try? modelContext.save()
        statusMessage = "Successfully approved and added \(importedCount) cards into \"\(targetDeck.name)\"!"
        showStatusAlert = true
    }
}
