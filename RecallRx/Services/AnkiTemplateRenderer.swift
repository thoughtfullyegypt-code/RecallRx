import Foundation
import CryptoKit

/// Renders the selected Anki card template, keeping sibling card identity and cloze targets distinct.
struct AnkiTemplateRenderer {
    struct RenderedCard {
        let id: UUID
        let front: String
        let back: String
        let noteType: NoteType
        let extra: String
        let firstAid: String
        let sketchy: String
        let pathoma: String
        let clinicalPearls: String
    }

    static func stableID(_ identity: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func render(
        card: AnkiImportPackage.ImportedCard,
        note: AnkiImportPackage.Note,
        model: AnkiImportPackage.NoteModel,
        deckName: String,
        collectionCreation: Date,
        mediaNames: [String: String]
    ) throws -> RenderedCard {
        guard note.fields.count == model.fieldNames.count, !model.fieldNames.contains(""), Set(model.fieldNames).count == model.fieldNames.count else {
            throw ApkgImporter.ApkgError.unsupportedCollection("Anki note fields do not match the note type's field definitions.")
        }
        let fields = Dictionary(uniqueKeysWithValues: zip(model.fieldNames, note.fields))
        let templateIndex = model.isCloze ? 0 : card.ordinal
        guard let template = model.templates[templateIndex] else {
            throw ApkgImporter.ApkgError.unsupportedCollection("An Anki card template is missing (ordinal \(card.ordinal)).")
        }
        var variables = fields
        variables["Tags"] = note.tags.joined(separator: " ")
        variables["Deck"] = deckName
        variables["Subdeck"] = deckName.components(separatedBy: "::").last ?? deckName
        variables["Card"] = "Card \(card.ordinal + 1)"
        let front = try expand(template.question, fields: variables, ordinal: card.ordinal, isCloze: model.isCloze)
        variables["FrontSide"] = front
        let answer = try expand(template.answer, fields: variables, ordinal: card.ordinal, isCloze: model.isCloze, answer: true)
        guard !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ApkgImporter.ApkgError.unsupportedCollection("Anki produced an empty question for card \(card.id).")
        }
        // Keep CSS with the rendered content, so imported field styling and media layout survive.
        let style = model.css.isEmpty ? "" : "<style>\(model.css)</style>"
        func field(_ names: [String]) -> String {
            for name in names {
                if let entry = fields.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
                    return rewriteMedia(entry.value, names: mediaNames)
                }
            }
            return ""
        }
        return RenderedCard(
            id: stableID("RecallRx.Anki.card:\(Int64(collectionCreation.timeIntervalSince1970)):\(note.guid.isEmpty ? String(note.id) : note.guid):\(card.id):\(card.ordinal)"),
            front: rewriteMedia(style + front, names: mediaNames),
            back: rewriteMedia(style + answer, names: mediaNames),
            // An imported cloze's back is already a fully rendered answer template.
            noteType: model.isCloze ? .cloze : .basic,
            extra: field(["Extra", "Back Extra", "Extra Notes"]),
            firstAid: field(["First Aid", "FirstAid", "Outline"]),
            sketchy: field(["Sketchy", "Visual"]),
            pathoma: field(["Pathoma", "Pathology"]),
            clinicalPearls: field(["Clinical Pearls", "ClinicalPearls", "Pearls"])
        )
    }

    private static func expand(_ template: String, fields: [String: String], ordinal: Int, isCloze: Bool, answer: Bool = false) throws -> String {
        var text = template
        // Conditional sections may be nested; resolve innermost matching pairs first.
        let conditional = try NSRegularExpression(pattern: #"\{\{([#^])([^{}]+)\}\}((?:(?!\{\{[#^]).)*?)\{\{/\2\}\}"#, options: [.dotMatchesLineSeparators])
        for _ in 0..<100 {
            let matches = conditional.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            guard !matches.isEmpty else { break }
            for match in matches.reversed() {
                let ns = text as NSString
                let name = ns.substring(with: match.range(at: 2))
                let present = !(fields[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let inverted = ns.substring(with: match.range(at: 1)) == "^"
                let replacement = present != inverted ? ns.substring(with: match.range(at: 3)) : ""
                text = ns.replacingCharacters(in: match.range, with: replacement)
            }
        }
        let tokens = try NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
        let matches = tokens.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        for match in matches.reversed() {
            let ns = text as NSString
            let token = ns.substring(with: match.range(at: 1))
            guard !token.hasPrefix("#"), !token.hasPrefix("^"), !token.hasPrefix("/") else {
                throw ApkgImporter.ApkgError.unsupportedCollection("An Anki card has an unsupported conditional template.")
            }
            let components = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let name = components.last ?? token
            var value = fields[name] ?? ""
            for filter in components.dropLast().reversed() {
                switch filter {
                case "cloze" where isCloze:
                    value = try renderClozes(value, target: ordinal + 1, answer: answer)
                case "text":
                    value = value.removingHTMLTags()
                case "type":
                    // RecallRx does not require typed answers; retain the expected text on the answer side.
                    value = answer ? value : "[Type your answer]"
                case "hint":
                    value = value.isEmpty ? "" : "<details><summary>\(name)</summary>\(value)</details>"
                default:
                    throw ApkgImporter.ApkgError.unsupportedCollection("Unsupported Anki template filter: \(filter). Export a compatible basic or cloze note type.")
                }
            }
            text = ns.replacingCharacters(in: match.range, with: value)
        }
        return text
    }

    private static func renderClozes(_ text: String, target: Int, answer: Bool) throws -> String {
        let expression = try NSRegularExpression(pattern: #"\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}"#, options: [.dotMatchesLineSeparators])
        var result = text
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard matches.contains(where: { Int((text as NSString).substring(with: $0.range(at: 1))) == target }) else {
            throw ApkgImporter.ApkgError.unsupportedCollection("Anki cloze card has no deletion for ordinal \(target - 1).")
        }
        for match in matches.reversed() {
            let ns = text as NSString
            let index = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let value = ns.substring(with: match.range(at: 2))
            let hint = match.range(at: 3).location == NSNotFound ? nil : ns.substring(with: match.range(at: 3))
            // Only this Anki card's deletion stays hidden. Sibling deletions remain readable.
            let replacement: String
            if index == target && !answer {
                replacement = "{{c1::\(value)\(hint.map { "::" + $0 } ?? "")}}"
            } else {
                replacement = value
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    static func rewriteMedia(_ text: String, names: [String: String]) -> String {
        var result = text
        for (original, renamed) in names where original != renamed {
            for source in Set([original, original.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? original]) {
                result = result.replacingOccurrences(of: "[sound:\(source)]", with: "[sound:\(renamed)]")
                let escaped = NSRegularExpression.escapedPattern(for: source)
                let pattern = #"(\bsrc\s*=\s*)(?:""# + escaped + #""|'"# + escaped + #"'|"# + escaped + #"(?=[\s/>]))"#
                if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let matches = expression.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
                    for match in matches.reversed() {
                        let prefix = (result as NSString).substring(with: match.range(at: 1))
                        result = (result as NSString).replacingCharacters(in: match.range, with: prefix + "\"" + renamed + "\"")
                    }
                }
            }
        }
        return result
    }
}
