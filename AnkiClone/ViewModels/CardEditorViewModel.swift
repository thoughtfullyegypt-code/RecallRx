import Foundation
import SwiftData
import Observation

@Observable
final class CardEditorViewModel {
    var modelContext: ModelContext
    var front: String = ""
    var back: String = ""
    var selectedNoteType: NoteType = .basic
    var selectedDeck: Deck?
    var tags: [String] = []
    var tagInput: String = ""
    var availableDecks: [Deck] = []
    
    var isEditing: Bool = false
    var editingCard: Card?
    var showPreview: Bool = false
    var clozeIndex: Int = 1
    
    // High-Yield Medical Fields
    var extra: String = ""
    var firstAid: String = ""
    var sketchy: String = ""
    var pathoma: String = ""
    var clinicalPearls: String = ""
    
    init(modelContext: ModelContext, deck: Deck? = nil, card: Card? = nil) {
        self.modelContext = modelContext
        self.selectedDeck = deck ?? card?.deck
        self.editingCard = card
        self.isEditing = card != nil
        
        if let card = card {
            self.front = card.front
            self.back = card.back
            self.selectedNoteType = card.noteType
            self.tags = card.tags
            self.selectedDeck = card.deck
            self.clozeIndex = ClozeParser.nextClozeIndex(in: card.front)
            self.extra = card.extra
            self.firstAid = card.firstAid
            self.sketchy = card.sketchy
            self.pathoma = card.pathoma
            self.clinicalPearls = card.clinicalPearls
        } else {
            self.front = ""
            self.back = ""
            self.selectedNoteType = .basic
            self.tags = []
            self.clozeIndex = 1
            self.extra = ""
            self.firstAid = ""
            self.sketchy = ""
            self.pathoma = ""
            self.clinicalPearls = ""
        }
        
        fetchDecks()
        if self.selectedDeck == nil {
            self.selectedDeck = availableDecks.first
        }
    }
    
    // MARK: - Decks
    
    func fetchDecks() {
        do {
            let descriptor = FetchDescriptor<Deck>(
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            availableDecks = try modelContext.fetch(descriptor)
        } catch {
            availableDecks = []
        }
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        guard selectedDeck != nil else { return false }
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if selectedNoteType == .cloze {
            return !trimmedFront.isEmpty && (trimmedFront.contains("{{c") || !trimmedBack.isEmpty)
        } else {
            return !trimmedFront.isEmpty && !trimmedBack.isEmpty
        }
    }
    
    // MARK: - Tags
    
    func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !tags.contains(trimmed) {
            tags.append(trimmed)
        }
        tagInput = ""
    }
    
    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
    
    // MARK: - Cloze Operations & Preview
    
    func insertCloze() {
        insertCloze(selectedText: "")
    }
    
    func insertCloze(selectedText: String) {
        let index = clozeIndex
        if selectedText.isEmpty {
            let snippet = "{{c\(index)::...}}"
            if front.isEmpty {
                front = snippet
            } else {
                front += " " + snippet
            }
        } else {
            let replacement = "{{c\(index)::\(selectedText)}}"
            front = front.replacingOccurrences(of: selectedText, with: replacement)
        }
        clozeIndex += 1
    }
    
    var clozeQuestionPreview: String {
        ClozeParser.renderFront(front)
    }
    
    var clozeAnswerPreview: String {
        ClozeParser.renderBack(front)
    }
    
    var clozePreview: String {
        if selectedNoteType == .cloze {
            let renderedFront = ClozeParser.renderFront(front)
            let renderedBack = ClozeParser.renderBack(front)
            if back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Question:\n\(renderedFront)\n\nAnswer:\n\(renderedBack)"
            } else {
                return "Question:\n\(renderedFront)\n\nAnswer:\n\(renderedBack)\n\nNotes:\n\(back)"
            }
        } else {
            return "Question:\n\(front)\n\nAnswer:\n\(back)"
        }
    }
    
    // MARK: - Save Card
    
    func save() -> Bool {
        guard isValid, let deck = selectedDeck else { return false }
        
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure tags exist in Tag persistence
        for tag in tags {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty else { continue }
            let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmedTag })
            if let existing = try? modelContext.fetch(descriptor), existing.isEmpty {
                modelContext.insert(Tag(name: trimmedTag))
            }
        }
        
        if isEditing, let card = editingCard {
            card.front = trimmedFront
            card.back = trimmedBack
            card.deck = deck
            card.tags = tags
            card.noteType = selectedNoteType
            card.extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            card.firstAid = firstAid.trimmingCharacters(in: .whitespacesAndNewlines)
            card.sketchy = sketchy.trimmingCharacters(in: .whitespacesAndNewlines)
            card.pathoma = pathoma.trimmingCharacters(in: .whitespacesAndNewlines)
            card.clinicalPearls = clinicalPearls.trimmingCharacters(in: .whitespacesAndNewlines)
            card.modifiedAt = Date()
        } else {
            if selectedNoteType == .basicReversed {
                // Forward card
                let primaryCard = Card(
                    front: trimmedFront,
                    back: trimmedBack,
                    deck: deck,
                    tags: tags,
                    noteType: .basicReversed,
                    extra: extra,
                    firstAid: firstAid,
                    sketchy: sketchy,
                    pathoma: pathoma,
                    clinicalPearls: clinicalPearls
                )
                modelContext.insert(primaryCard)
                
                // Reversed card
                let reversedCard = Card(
                    front: trimmedBack,
                    back: trimmedFront,
                    deck: deck,
                    tags: tags,
                    noteType: .basicReversed,
                    extra: extra,
                    firstAid: firstAid,
                    sketchy: sketchy,
                    pathoma: pathoma,
                    clinicalPearls: clinicalPearls
                )
                modelContext.insert(reversedCard)
            } else {
                let newCard = Card(
                    front: trimmedFront,
                    back: trimmedBack,
                    deck: deck,
                    tags: tags,
                    noteType: selectedNoteType,
                    extra: extra,
                    firstAid: firstAid,
                    sketchy: sketchy,
                    pathoma: pathoma,
                    clinicalPearls: clinicalPearls
                )
                modelContext.insert(newCard)
            }
        }
        
        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }
}
