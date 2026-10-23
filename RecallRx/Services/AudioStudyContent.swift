import Foundation

/// Spoken question and grading answers derived from the same note, without revealing deletions.
struct AudioStudyContent: Equatable, Sendable {
    let question: String
    let expectedAnswers: [String]
    let isCloze: Bool

    var expectedAnswer: String { expectedAnswers.joined(separator: "; ") }

    private static let clozePattern = #"\{\{c([1-9][0-9]*)::([^{}]*?)\}\}"#

    /// Visual notes, malformed deletions and notes without a spoken answer are intentionally unsupported.
    static func make(front: String, back: String, noteType: NoteType) -> AudioStudyContent? {
        guard noteType != .imageOcclusion else { return nil }
        let decodedFront = decodeEntities(front)
        guard !containsMedia(decodedFront) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: clozePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let matches = regex.matches(in: decodedFront, range: NSRange(decodedFront.startIndex..., in: decodedFront))
        var question = decodedFront
        var answers: [String] = []

        if !matches.isEmpty {
            // Every deletion stays hidden, including hints that might themselves disclose the answer.
            for match in matches.reversed() {
                guard let range = Range(match.range, in: question),
                      let contentRange = Range(match.range(at: 2), in: decodedFront) else { return nil }
                let content = String(decodedFront[contentRange])
                let answer = plainText(content.components(separatedBy: "::")[0])
                guard !answer.isEmpty, !containsMedia(content) else { return nil }
                answers.insert(answer, at: 0)
                question.replaceSubrange(range, with: "blank")
            }
            // A partially parsed or nested deletion must never be read aloud.
            guard !question.contains("{{"), !question.contains("}}") else { return nil }
        } else {
            let decodedBack = decodeEntities(back)
            guard noteType != .cloze,
                  !decodedFront.contains("{{"), !decodedFront.contains("}}"),
                  !containsMedia(decodedBack), !decodedBack.contains("{{"), !decodedBack.contains("}}") else { return nil }
            let answer = plainText(decodedBack)
            guard !answer.isEmpty else { return nil }
            answers = [answer]
        }
        question = plainText(question)
        guard !question.isEmpty, question.count <= 220 else { return nil }
        var uniqueAnswers: [String] = []
        for answer in answers where !uniqueAnswers.contains(where: { $0.caseInsensitiveCompare(answer) == .orderedSame }) {
            uniqueAnswers.append(answer)
        }
        let combinedAnswer = uniqueAnswers.joined(separator: "; ")
        guard !combinedAnswer.isEmpty, combinedAnswer.count <= 220 else { return nil }
        return AudioStudyContent(question: question, expectedAnswers: uniqueAnswers, isCloze: !matches.isEmpty)
    }

    /// General speech text always masks deletions rather than stripping their syntax and exposing answers.
    static func sanitize(_ text: String) -> String {
        let decoded = decodeEntities(text)
        guard let regex = try? NSRegularExpression(pattern: clozePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return "" }
        let masked = regex.stringByReplacingMatches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded), withTemplate: "blank")
        guard !masked.contains("{{"), !masked.contains("}}") else { return "" }
        return plainText(masked)
    }

    private static func containsMedia(_ text: String) -> Bool {
        text.range(of: #"<(?:img|svg|audio|video|script|style)\b|\[sound:"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func plainText(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "<", with: " less than ")
        clean = clean.replacingOccurrences(of: ">", with: " greater than ")
        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        var decoded = text
        let replacements = [("&amp;", "&"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")]
        for (entity, value) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-f]+|[0-9]+);"#, options: .caseInsensitive) {
            for match in regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed() {
                guard let fullRange = Range(match.range, in: decoded),
                      let valueRange = Range(match.range(at: 1), in: decoded) else { continue }
                let encoded = String(decoded[valueRange])
                let isHex = encoded.lowercased().hasPrefix("x")
                let digits = isHex ? String(encoded.dropFirst()) : encoded
                guard let value = UInt32(digits, radix: isHex ? 16 : 10), let scalar = UnicodeScalar(value) else { continue }
                decoded.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        return decoded
    }
}
