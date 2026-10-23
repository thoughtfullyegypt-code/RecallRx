import Foundation
import PDFKit
import NaturalLanguage
import SwiftData

/// Generated Card Preview from PDF / Slide Parsing with Safety Markers
struct GeneratedCardCandidate: Identifiable, Sendable {
    let id: UUID
    var front: String
    var back: String
    var noteType: NoteType
    var tags: [String]
    let sourceSlide: Int
    var sourcePassage: String
    var clinicalPearl: String
    var hasNumericalWarning: Bool
    var numericalWarningMessage: String?
    var isSelected: Bool
    var wasEdited: Bool
    
    init(
        id: UUID = UUID(),
        front: String,
        back: String,
        noteType: NoteType,
        tags: [String],
        sourceSlide: Int,
        sourcePassage: String,
        clinicalPearl: String,
        hasNumericalWarning: Bool = false,
        numericalWarningMessage: String? = nil,
        isSelected: Bool = true,
        wasEdited: Bool = false
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.noteType = noteType
        self.tags = tags
        self.sourceSlide = sourceSlide
        self.sourcePassage = sourcePassage
        self.clinicalPearl = clinicalPearl
        self.hasNumericalWarning = hasNumericalWarning
        self.numericalWarningMessage = numericalWarningMessage
        self.isSelected = isSelected
        self.wasEdited = wasEdited
    }
}

/// Telemetry Tracker for User Edits and Rejections of AI Generated Cards
final class PDFCardTelemetry: @unchecked Sendable {
    static let shared = PDFCardTelemetry()
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func logGenerated(count: Int) {
        increment("telemetry_cards_generated", by: count)
    }
    
    func logApproved(count: Int) {
        increment("telemetry_cards_approved", by: count)
    }
    
    func logEdited(count: Int = 1) {
        increment("telemetry_cards_edited", by: count)
    }
    
    func logRejected(count: Int) {
        increment("telemetry_cards_rejected", by: count)
    }
    
    var stats: (generated: Int, approved: Int, edited: Int, rejected: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (
            defaults.integer(forKey: "telemetry_cards_generated"),
            defaults.integer(forKey: "telemetry_cards_approved"),
            defaults.integer(forKey: "telemetry_cards_edited"),
            defaults.integer(forKey: "telemetry_cards_rejected")
        )
    }

    private func increment(_ key: String, by count: Int) {
        guard count > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        defaults.set(defaults.integer(forKey: key) + count, forKey: key)
    }
}

/// Offline On-Device PDF & Slide Card Synthesis Engine
/// Extracts lecture slide text and clinical bullet points using PDFKit and NaturalLanguage,
/// synthesizing high-yield medical Q&A and cloze cards without any external API.
/// Incorporates safety markers for drug dosages, lab values, and numerical facts.
final class PDFCardGenerator {
    
    // MARK: - Safety Regex Patterns for Dosages, Lab Values & Numbers
    private static let dosageRegex = try? NSRegularExpression(
        pattern: #"(?i)\b\d+(\.\d+)?\s*(mg|mcg|µg|g|kg|meq|mmol|units|iu|ml|mg\/kg|mcg\/kg)\b"#,
        options: []
    )
    
    private static let labValueRegex = try? NSRegularExpression(
        pattern: #"(?i)\b\d+(\.\d+)?\s*(mmol\/l|mg\/dl|g\/dl|meq\/l|mmhg|bpm|%|pg\/ml|ng\/ml)\b"#,
        options: []
    )
    
    private static let clinicalCutoffRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(pao2|paco2|ph|bp|hgb|wbc|platelets|inr|creatinine|bun|sodium|potassium)\s*[<=>:]\s*\d+"#,
        options: []
    )
    
    // MARK: - PDF Processing
    
    /// Parses a PDF file from URL and synthesizes flashcards
    static func generateCards(
        from pdfURL: URL,
        deckName: String = "Lecture Deck",
        telemetry: PDFCardTelemetry = .shared
    ) -> [GeneratedCardCandidate] {
        guard let document = PDFDocument(url: pdfURL) else { return [] }
        
        var candidates: [GeneratedCardCandidate] = []
        let pageCount = document.pageCount
        
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageText.isEmpty else {
                continue
            }
            
            let slideNumber = pageIndex + 1
            let slideCards = extractCardsFromSlideText(pageText, slideNumber: slideNumber, lectureName: deckName)
            candidates.append(contentsOf: slideCards)
        }
        
        telemetry.logGenerated(count: candidates.count)
        return candidates
    }
    
    /// Parses plain text notes (e.g. copied lecture outline)
    static func generateCards(
        fromPlainText text: String,
        lectureName: String = "Notes",
        telemetry: PDFCardTelemetry = .shared
    ) -> [GeneratedCardCandidate] {
        let cards = extractCardsFromSlideText(text, slideNumber: 1, lectureName: lectureName)
        telemetry.logGenerated(count: cards.count)
        return cards
    }
    
    // MARK: - Clinical Concept Extraction & Pattern Matching
    
    private static func extractCardsFromSlideText(
        _ text: String,
        slideNumber: Int,
        lectureName: String
    ) -> [GeneratedCardCandidate] {
        var results: [GeneratedCardCandidate] = []
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 10 }
        
        // Tag base from lecture name
        let cleanTag = lectureName.replacingOccurrences(of: " ", with: "_")
        let tags = ["LectureNotes", cleanTag, "Slide_\(slideNumber)"]
        
        for line in lines {
            // Pattern 1: Definitions & Hallmarks ("X is characterized by Y", "Hallmark of X is Y")
            if let card = parseDefinitionPattern(line, slide: slideNumber, tags: tags) {
                results.append(card)
                continue
            }
            
            // Pattern 2: Drug Mechanism & Treatments ("Treatment for X is Y", "Drug of choice: Y")
            if let card = parsePharmacologyPattern(line, slide: slideNumber, tags: tags) {
                results.append(card)
                continue
            }
            
            // Pattern 3: Key Clinical Triad or Presentation ("Triad of X: A, B, C", "Symptoms: ...")
            if let card = parseClinicalPresentationPattern(line, slide: slideNumber, tags: tags) {
                results.append(card)
                continue
            }
            
            // Pattern 4: Colon Separated Key-Value ("Diagnosis: Biopsy showing X")
            if let card = parseKeyValuePattern(line, slide: slideNumber, tags: tags) {
                results.append(card)
                continue
            }
        }
        
        // Fallback: If no structured patterns matched on this page, synthesize a high-yield summary cloze
        if results.isEmpty && lines.count >= 2 {
            let combined = lines.prefix(3).joined(separator: " ")
            if combined.count > 40 {
                let clozeCard = synthesizeClozeCard(text: combined, slide: slideNumber, tags: tags)
                results.append(clozeCard)
            }
        }
        
        return results
    }
    
    // MARK: - Specialized Synthesizers with Safety Checks
    
    private static func parseDefinitionPattern(_ line: String, slide: Int, tags: [String]) -> GeneratedCardCandidate? {
        let lower = line.lowercased()
        let markers = [" is characterized by ", " is defined as ", " refers to ", " hallmark is ", " hallmark of "]
        for marker in markers {
            if let range = lower.range(of: marker) {
                let subject = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let predicate = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard subject.count > 3 && predicate.count > 5 else { continue }
                
                let (hasWarning, warningMsg, formattedBack) = inspectSafety(text: predicate, baseBack: "\(predicate)\n\n<i>(Slide \(slide))</i>")
                
                let front = "What is the key hallmark/definition of <b>\(subject)</b>?"
                
                return GeneratedCardCandidate(
                    front: front,
                    back: formattedBack,
                    noteType: .basic,
                    tags: tags + ["Pathology"],
                    sourceSlide: slide,
                    sourcePassage: line,
                    clinicalPearl: "\(subject): \(predicate)",
                    hasNumericalWarning: hasWarning,
                    numericalWarningMessage: warningMsg
                )
            }
        }
        return nil
    }
    
    private static func parsePharmacologyPattern(_ line: String, slide: Int, tags: [String]) -> GeneratedCardCandidate? {
        let lower = line.lowercased()
        let pharmaMarkers = ["first-line treatment for ", "drug of choice for ", "treatment of choice: ", "mechanism of action: ", "moa: "]
        
        for marker in pharmaMarkers {
            if let range = lower.range(of: marker) {
                let prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let detail = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                guard detail.count > 3 else { continue }
                
                let condition = prefix.isEmpty ? "this condition" : prefix
                let front = "What is the \(marker.trimmingCharacters(in: .punctuationCharacters)) <b>\(condition)</b>?"
                
                let (hasWarning, warningMsg, formattedBack) = inspectSafety(text: detail, baseBack: "\(detail)\n\n<i>(Slide \(slide))</i>")
                
                return GeneratedCardCandidate(
                    front: front,
                    back: formattedBack,
                    noteType: .basic,
                    tags: tags + ["Pharmacology"],
                    sourceSlide: slide,
                    sourcePassage: line,
                    clinicalPearl: line,
                    hasNumericalWarning: hasWarning,
                    numericalWarningMessage: warningMsg
                )
            }
        }
        return nil
    }
    
    private static func parseClinicalPresentationPattern(_ line: String, slide: Int, tags: [String]) -> GeneratedCardCandidate? {
        let lower = line.lowercased()
        if lower.contains("triad of ") || lower.contains("classic triad") || lower.contains("presentation: ") {
            let front = "What is the classic clinical presentation / triad described in:\n\"\(line.prefix(60))...\"?"
            let (hasWarning, warningMsg, formattedBack) = inspectSafety(text: line, baseBack: "\(line)\n\n<i>(Slide \(slide))</i>")
            
            return GeneratedCardCandidate(
                front: front,
                back: formattedBack,
                noteType: .basic,
                tags: tags + ["ClinicalTriad"],
                sourceSlide: slide,
                sourcePassage: line,
                clinicalPearl: line,
                hasNumericalWarning: hasWarning,
                numericalWarningMessage: warningMsg
            )
        }
        return nil
    }
    
    private static func parseKeyValuePattern(_ line: String, slide: Int, tags: [String]) -> GeneratedCardCandidate? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        
        let medicalKeys = ["diagnosis", "treatment", "etiology", "pathophysiology", "symptoms", "adverse effects", "histology", "biopsy"]
        if medicalKeys.contains(where: { key.lowercased().contains($0) }) && value.count > 5 {
            let front = "<b>\(key.capitalized)</b> for this clinical condition:"
            let (hasWarning, warningMsg, formattedBack) = inspectSafety(text: value, baseBack: "\(value)\n\n<i>(Slide \(slide))</i>")
            
            return GeneratedCardCandidate(
                front: front,
                back: formattedBack,
                noteType: .basic,
                tags: tags,
                sourceSlide: slide,
                sourcePassage: line,
                clinicalPearl: "\(key): \(value)",
                hasNumericalWarning: hasWarning,
                numericalWarningMessage: warningMsg
            )
        }
        return nil
    }
    
    private static func synthesizeClozeCard(text: String, slide: Int, tags: [String]) -> GeneratedCardCandidate {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text
        
        let words = text.components(separatedBy: .whitespaces)
        var clozeTarget = ""
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass) { tag, tokenRange in
            if tag == .noun || tag == .organizationName || tag == .placeName {
                let candidate = String(text[tokenRange])
                if candidate.count > 5 && clozeTarget.isEmpty {
                    clozeTarget = candidate
                }
            }
            return true
        }
        
        let clozeText: String
        if !clozeTarget.isEmpty && text.contains(clozeTarget) {
            clozeText = text.replacingOccurrences(of: clozeTarget, with: "{{c1::\(clozeTarget)}}")
        } else if let firstWord = words.first(where: { $0.count > 5 }) {
            clozeText = text.replacingOccurrences(of: firstWord, with: "{{c1::\(firstWord)}}")
        } else {
            clozeText = "{{c1::\(text)}}"
        }
        
        let (hasWarning, warningMsg, formattedBack) = inspectSafety(text: text, baseBack: "Slide \(slide) Context")
        
        return GeneratedCardCandidate(
            front: clozeText,
            back: formattedBack,
            noteType: .cloze,
            tags: tags,
            sourceSlide: slide,
            sourcePassage: text,
            clinicalPearl: text,
            hasNumericalWarning: hasWarning,
            numericalWarningMessage: warningMsg
        )
    }
    
    // MARK: - Safety Inspection Helper
    
    /// Inspects text for dosages, lab values, or critical clinical numbers
    static func inspectSafety(text: String, baseBack: String) -> (hasWarning: Bool, warningMsg: String?, formattedBack: String) {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var reasons: [String] = []
        
        if let dosageRegex = dosageRegex, dosageRegex.firstMatch(in: text, options: [], range: nsRange) != nil {
            reasons.append("drug dosage")
        }
        
        if let labValueRegex = labValueRegex, labValueRegex.firstMatch(in: text, options: [], range: nsRange) != nil {
            reasons.append("lab reference values")
        }
        
        if let clinicalCutoffRegex = clinicalCutoffRegex, clinicalCutoffRegex.firstMatch(in: text, options: [], range: nsRange) != nil {
            reasons.append("clinical cutoffs / vitals")
        }
        
        if !reasons.isEmpty {
            let warningText = "⚠️ Verify against your source: contains \(reasons.joined(separator: " and "))"
            let backWithWarning = "\(baseBack)\n\n<p style=\"color: #E65100; font-size: 11px; font-weight: bold;\">\(warningText)</p>"
            return (true, warningText, backWithWarning)
        }
        
        return (false, nil, baseBack)
    }
}
