import Foundation

struct ClozeParser {
    // Regex pattern for {{cN::text}} and {{cN::text::hint}}
    private static let clozeRegex: NSRegularExpression? = {
        let pattern = #"\{\{c(\d+)::(.*?)\}\}"#
        return try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }()
    
    struct ClozeField {
        let index: Int
        let answer: String
        let hint: String?
        let fullMatch: String
        let range: Range<String.Index>
    }
    
    /// Extract all cloze deletions from text
    static func parse(_ text: String) -> [ClozeField] {
        guard let regex = clozeRegex, !text.isEmpty else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        
        var fields: [ClozeField] = []
        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let indexRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text),
                  let index = Int(text[indexRange]) else {
                continue
            }
            
            let fullMatch = String(text[fullRange])
            let content = String(text[contentRange])
            
            let answer: String
            let hint: String?
            
            if let colonRange = content.range(of: "::") {
                answer = String(content[..<colonRange.lowerBound])
                let rawHint = String(content[colonRange.upperBound...])
                hint = rawHint.isEmpty ? nil : rawHint
            } else {
                answer = content
                hint = nil
            }
            
            fields.append(ClozeField(
                index: index,
                answer: answer,
                hint: hint,
                fullMatch: fullMatch,
                range: fullRange
            ))
        }
        
        return fields
    }
    
    /// Replace cloze deletions with [...] or [hint] on front
    /// If revealingIndex is specified, only hide that index
    static func renderFront(_ text: String, revealingIndex: Int? = nil) -> String {
        let fields = parse(text)
        guard !fields.isEmpty else { return text }
        
        var result = text
        for field in fields.reversed() {
            let replacement: String
            if let targetIndex = revealingIndex {
                if field.index == targetIndex {
                    if let hint = field.hint, !hint.isEmpty {
                        replacement = "[\(hint)]"
                    } else {
                        replacement = "[...]"
                    }
                } else {
                    replacement = field.answer
                }
            } else {
                if let hint = field.hint, !hint.isEmpty {
                    replacement = "[\(hint)]"
                } else {
                    replacement = "[...]"
                }
            }
            result.replaceSubrange(field.range, with: replacement)
        }
        return result
    }
    
    /// Replace cloze deletions with the answer text (highlighted)
    static func renderBack(_ text: String, revealingIndex: Int? = nil) -> String {
        let fields = parse(text)
        guard !fields.isEmpty else { return text }
        
        var result = text
        for field in fields.reversed() {
            let replacement: String
            if let targetIndex = revealingIndex {
                if field.index == targetIndex {
                    replacement = "**\(field.answer)**"
                } else {
                    replacement = field.answer
                }
            } else {
                replacement = "**\(field.answer)**"
            }
            result.replaceSubrange(field.range, with: replacement)
        }
        return result
    }
    
    /// Count unique cloze indices
    static func clozeCount(_ text: String) -> Int {
        let fields = parse(text)
        let uniqueIndices = Set(fields.map { $0.index })
        return uniqueIndices.count
    }
    
    /// Wrap text in {{cN::}} syntax
    static func insertCloze(in text: String, selection: Range<String.Index>?, index: Int) -> String {
        if let selection = selection, !selection.isEmpty {
            let selectedText = String(text[selection])
            var result = text
            result.replaceSubrange(selection, with: "{{c\(index)::\(selectedText)}}")
            return result
        } else if let selection = selection {
            var result = text
            result.insert(contentsOf: "{{c\(index)::}}", at: selection.lowerBound)
            return result
        } else {
            return text.isEmpty ? "{{c\(index)::}}" : "\(text) {{c\(index)::}}"
        }
    }
    
    /// Returns the next available cloze index
    static func nextClozeIndex(in text: String) -> Int {
        let fields = parse(text)
        guard let maxIndex = fields.map({ $0.index }).max() else {
            return 1
        }
        return maxIndex + 1
    }
}
