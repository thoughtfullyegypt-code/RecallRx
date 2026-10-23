import Foundation

/// Exact question-ID matching with source evidence on both tag and content paths.
enum QuestionIDMatcher {
    private static let qidPattern = #"(?<![a-z0-9])qid[\s_:\-]+([a-z0-9]+)(?![a-z0-9])"#
    private static let sourcePattern = #"(?<![a-z0-9])(uworld|amboss)(?![a-z0-9])"#

    static func parseInput(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",; \n\r\t")
        var result: [String] = []
        for token in text.components(separatedBy: separators) {
            guard let identifier = normalizedID(token), !result.contains(identifier) else { continue }
            result.append(identifier)
        }
        return result
    }

    /// `source` is nil for All QBanks, otherwise the canonical `uworld` or `amboss` name.
    static func matches(qid: String, source: String?, tags: [String], front: String, back: String) -> Bool {
        guard let identifier = normalizedID(qid) else { return false }
        let selectedSource = source?.lowercased()
        if let selectedSource, !["uworld", "amboss"].contains(selectedSource) { return false }
        let tagSources = Set(tags.flatMap { sourceNames(in: $0) })

        for tag in tags {
            let localSources = Set(sourceNames(in: tag))
            let identifiers = explicitIDs(in: tag).map(\.value)
            let hasID = identifiers.contains(identifier) || normalizedID(tag) == identifier
            guard hasID else { continue }
            guard let selectedSource else { return true }
            if localSources == Set([selectedSource]) { return true }
            if localSources.isEmpty && tagSources == Set([selectedSource]) { return true }
        }

        for content in [front, back] {
            // Keep matching local to a line/sentence so another source elsewhere cannot qualify a QID.
            let plain = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            for segment in plain.components(separatedBy: CharacterSet(charactersIn: "\n\r.;")) {
                let identifiers = explicitIDs(in: segment)
                for occurrence in identifiers where occurrence.value == identifier {
                    guard let selectedSource else { return true }
                    let localSource = sourceForOccurrence(occurrence.range, identifiers: identifiers, in: segment)
                    if let localSource {
                        if localSource == selectedSource { return true }
                    } else if sourceNames(in: segment).isEmpty && tagSources == Set([selectedSource]) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func normalizedID(_ input: String) -> String? {
        let value = input.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !value.isEmpty else { return nil }
        if let explicit = explicitIDs(in: value).last { return explicit.value }
        if value.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil {
            guard !["qid", "uworld", "amboss"].contains(value) else { return nil }
            return value
        }
        // Source-qualified shorthand, such as UWorld_123 or #AMBOSS::123.
        if let regex = try? NSRegularExpression(pattern: #"^(?:uworld|amboss)(?:[_:\-]+)([a-z0-9]+)$"#),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let range = Range(match.range(at: 1), in: value) {
            return String(value[range])
        }
        // Imported hierarchical source tags sometimes omit QID_ but end in a numeric ID.
        if !sourceNames(in: value).isEmpty {
            let last = value.components(separatedBy: CharacterSet.alphanumerics.inverted).last ?? ""
            if !last.isEmpty, last.allSatisfy(\.isNumber) { return last }
        }
        return nil
    }

    private static func explicitIDs(in text: String) -> [(value: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: qidPattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return (String(text[range]).lowercased(), match.range)
        }
    }

    private static func sourceNames(in text: String) -> [String] {
        sourceOccurrences(in: text).map(\.value)
    }

    private static func sourceOccurrences(in text: String) -> [(value: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: sourcePattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return (String(text[range]).lowercased(), match.range)
        }
    }

    private static func sourceForOccurrence(_ range: NSRange, identifiers: [(value: String, range: NSRange)], in text: String) -> String? {
        let sources = sourceOccurrences(in: text)
        let nextID = identifiers.first(where: { $0.range.location > range.location })?.range.location
        let end = nextID ?? (text as NSString).length
        let tailRange = NSRange(location: NSMaxRange(range), length: max(0, end - NSMaxRange(range)))
        let tail = (text as NSString).substring(with: tailRange)
        // A direct trailing attribution is stronger than a source inherited from an earlier ID.
        if let regex = try? NSRegularExpression(pattern: #"^\s*[\(\[]\s*(uworld|amboss)\b"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
           let sourceRange = Range(match.range(at: 1), in: tail) {
            return String(tail[sourceRange]).lowercased()
        }
        if let preceding = sources.last(where: { NSMaxRange($0.range) <= range.location }) {
            return preceding.value
        }
        // A source immediately before the next QID must not be borrowed for this one.
        guard nextID == nil else { return nil }
        return sources.first(where: { $0.range.location >= NSMaxRange(range) })?.value
    }
}
