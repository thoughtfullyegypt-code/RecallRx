import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// UWorld Incorrects Synchronization & Clinical Concept Flashcard Engine
/// Parses user-provided missed question IDs (clipboard or text), checks for duplicates, and creates high-yield cards.
struct UWorldSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Deck.name) private var decks: [Deck]
    
    var autoLoadSample: Bool = false
    
    @State private var inputText: String = ""
    @State private var selectedDeck: Deck?
    @State private var detectedQIDs: [UWorldQuestionStatus] = []
    @State private var isProcessing: Bool = false
    @State private var generationStatus: String?
    @State private var showResultAlert: Bool = false
    
    // Status representation for each detected question
    struct UWorldQuestionStatus: Identifiable {
        let id: Int // QID
        let isAlreadyImported: Bool
        let topic: String?
        let system: String?
    }
    
    var body: some View {
        NavigationStack {
            instantParserView
            .navigationTitle("UWorld Incorrects Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadSampleIncorrects()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Sample Test")
                        }
                        .font(.caption.bold())
                    }
                }
            }
            .alert("AI Card Generation", isPresented: $showResultAlert) {
                Button("Done") {
                    if generationStatus?.contains("Successfully") == true {
                        dismiss()
                    }
                }
            } message: {
                Text(generationStatus ?? "")
            }
            .onAppear {
                if selectedDeck == nil {
                    selectedDeck = OnDeviceMedicalAIEngine.getOrCreateUWorldDeck(in: modelContext)
                }
                if autoLoadSample && inputText.isEmpty {
                    loadSampleIncorrects()
                }
            }
        }
    }
    
    // MARK: - Tab 1: Instant Parser View
    private var instantParserView: some View {
        Form {
            Section("Destination Deck") {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedDeck?.name ?? "UWorld Incorrects")
                                .font(.subheadline.weight(.semibold))
                            Text("Dedicated deck for missed questions")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "cross.case.fill")
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                    
                    Menu {
                        ForEach(decks) { deck in
                            Button {
                                selectedDeck = deck
                            } label: {
                                HStack {
                                    Text(deck.name)
                                    if selectedDeck?.id == deck.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            selectedDeck = OnDeviceMedicalAIEngine.getOrCreateUWorldDeck(in: modelContext)
                        } label: {
                            Label("UWorld Incorrects (Default)", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Text("Change")
                            .font(.subheadline.bold())
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste UWorld Test Analysis, Score Report, or QID List:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $inputText)
                        .frame(height: 75)
                        .font(.system(.caption, design: .monospaced))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    
                    HStack {
                        Button {
                            parseInputText()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Scan QIDs")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Button {
                            pasteFromClipboard()
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                Text("Paste")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Clear") {
                            inputText = ""
                            detectedQIDs.removeAll()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Input Data")
            } footer: {
                Text("Supports raw Question IDs (e.g., '1052, 2190, 8431') or copied review tables from UWorld.")
            }
            
            if !detectedQIDs.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Found \(detectedQIDs.count) Questions")
                                .font(.headline)
                            Spacer()
                            let newCount = detectedQIDs.filter { !$0.isAlreadyImported }.count
                            Text("\(newCount) New • \(detectedQIDs.count - newCount) Existing")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        
                        ForEach(detectedQIDs) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("QID \(item.id)")
                                            .font(.subheadline.bold())
                                        if let topic = item.topic {
                                            Text("• \(topic)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    if let system = item.system {
                                        Text(system)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                Spacer()
                                
                                if item.isAlreadyImported {
                                    Text("Already in Deck")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.15))
                                        .foregroundColor(.secondary)
                                        .clipShape(Capsule())
                                } else {
                                    Text("+ New Card")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.18))
                                        .foregroundColor(.green)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        
                        let pendingCount = detectedQIDs.filter { !$0.isAlreadyImported }.count
                        Button {
                            generateCardsForNewIncorrects()
                        } label: {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                    Text("Synthesizing AI Cards...")
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Create \(pendingCount) AI Flashcards (No Duplicates)")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingCount == 0 || isProcessing)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Deduplication & Extraction Preview")
                } footer: {
                    Text("Guaranteed Zero Duplicates: Any question you have previously imported will be strictly skipped.")
                }
            }
        }
    }
    
    // MARK: - Actions & Parsing
    private func pasteFromClipboard() {
        #if canImport(UIKit)
        if let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty {
            self.inputText = clipboardString
            self.parseInputText()
        }
        #endif
    }
    
    private func parseInputText() {
        let pattern = #"(?:QID[\s_:]*|#)?(\d{4,6})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        
        let nsString = inputText as NSString
        let matches = regex.matches(in: inputText, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var seenQIDs = Set<Int>()
        var results: [UWorldQuestionStatus] = []
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: inputText),
               let qid = Int(inputText[range]),
               !seenQIDs.contains(qid) {
                seenQIDs.insert(qid)
                
                let alreadyImported = OnDeviceMedicalAIEngine.isQIDAlreadyImported(qid, in: modelContext)
                let concept = OnDeviceMedicalAIEngine.knowledgeBase[qid]
                
                results.append(UWorldQuestionStatus(
                    id: qid,
                    isAlreadyImported: alreadyImported,
                    topic: concept?.topic,
                    system: concept?.system
                ))
            }
        }
        
        detectedQIDs = results
    }
    
    private func loadSampleIncorrects() {
        // High-yield Step 1/2 incorrect test block
        inputText = """
        UWorld Test Block 4 (Cardio, Endocrine, Neuro, Rheum) - 40 Questions
        Score: 68% (Incorrects: 13)
        
        QID 1052 - Incorrect - Wolff-Parkinson-White accessory pathway (Bundle of Kent)
        QID 2190 - Incorrect - Tetralogy of Fallot tet spell hemodynamics (squatting SVR)
        QID 1894 - Incorrect - Diabetic Ketoacidosis potassium check before insulin
        QID 8431 - Incorrect - Giant Cell Arteritis immediate steroids before biopsy
        QID 1420 - Incorrect - Pneumocystis jirovecii TMP-SMX and steroid criteria
        QID 3115 - Incorrect - Myasthenia Gravis vs Lambert-Eaton ACh receptor autoantibodies
        QID 4820 - Incorrect - Celiac Disease anti-tTG IgA and duodenal villous atrophy
        """
        parseInputText()
    }
    
    private func generateCardsForNewIncorrects() {
        let deck = selectedDeck ?? OnDeviceMedicalAIEngine.getOrCreateUWorldDeck(in: modelContext)
        
        isProcessing = true
        var createdCount = 0
        var skippedCount = 0
        
        for item in detectedQIDs {
            if item.isAlreadyImported {
                skippedCount += 1
                continue
            }
            
            if let _ = OnDeviceMedicalAIEngine.generateCardForIncorrect(
                qid: item.id,
                customNotes: nil,
                targetDeck: deck,
                context: modelContext
            ) {
                createdCount += 1
            }
        }
        
        isProcessing = false
        generationStatus = "Successfully generated \(createdCount) flashcards into '\(deck.name)' with zero duplicates!\n(\(skippedCount) existing questions were safely skipped)."
        showResultAlert = true
        
        // Refresh statuses
        parseInputText()
    }
}
