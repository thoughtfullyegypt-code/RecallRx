import Foundation

/// Pure speech grading logic; no recording, playback, permissions, or persistence side effects.
enum AudioStudyAnswerEvaluator {
    /// Ratings intentionally use only Again (0), Hard (1), and Good (2).
    /// A multi-blank answer is Good only when every distinct hidden answer is recalled.
    static func evaluate(spoken: String, expectedAnswers: [String]) -> (rating: Int, similarity: Double) {
        let normalized = spoken.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let surrender = ["i don't know", "i do not know", "no idea", "pass"]
        guard !normalized.isEmpty, !surrender.contains(normalized), !expectedAnswers.isEmpty else { return (0, 0) }
        let scores = expectedAnswers.map { similarity(spoken: normalized, expected: $0) }
        let score = scores.reduce(0, +) / Double(scores.count)
        if scores.allSatisfy({ $0 >= 0.70 }) { return (2, score) }
        if scores.contains(where: { $0 >= 0.35 }) { return (1, score) }
        return (0, score)
    }

    static func voiceCommand(in text: String) -> DrivingVoiceCommand? {
        let normalized = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        switch normalized {
        case "repeat", "repeat question", "repeat the question", "repeat that please", "please repeat", "could you repeat that please", "say again", "say that again":
            return .repeatQuestion
        case "skip", "skip card", "skip this card", "next", "next card":
            return .skipCard
        case "hint", "a hint", "give me a hint", "please give me a hint":
            return .requestHint
        case "stop", "stop session", "stop the session", "end drive", "pause", "pause session":
            return .stopSession
        default:
            return nil
        }
    }

    static func contextualVocabulary(for answers: [String]) -> [String] {
        let answer = answers.joined(separator: " ").lowercased()
        var vocabulary = answer.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
        for (key, synonyms) in medicalSynonyms where answer.contains(key) {
            vocabulary.append(contentsOf: synonyms)
        }
        return Array(Set(vocabulary)).sorted()
    }
    // Medical synonyms dictionary for fuzzy matching
    private static let medicalSynonyms: [String: [String]] = [
        "mi": ["myocardial infarction", "heart attack"],
        "myocardial infarction": ["mi", "heart attack"],
        "heart attack": ["mi", "myocardial infarction"],
        "pe": ["pulmonary embolism"],
        "pulmonary embolism": ["pe"],
        "hcm": ["hypertrophic cardiomyopathy", "hocm"],
        "hypertrophic cardiomyopathy": ["hcm", "hocm"],
        "chf": ["congestive heart failure", "heart failure"],
        "heart failure": ["chf", "congestive heart failure"],
        "nsaid": ["nonsteroidal anti-inflammatory", "ibuprofen", "naproxen", "indomethacin"],
        "nsaids": ["nonsteroidal anti-inflammatory drugs", "ibuprofen", "naproxen", "indomethacin"],
        "copd": ["chronic obstructive pulmonary disease"],
        "pcr": ["polymerase chain reaction"],
        "gerd": ["acid reflux", "gastroesophageal reflux disease"],
        "ace inhibitor": ["lisinopril", "enalapril", "ramipril"],
        "arb": ["losartan", "valsartan"],
        "dvt": ["deep vein thrombosis"],
        "pci": ["percutaneous coronary intervention", "angioplasty"],
        "percutaneous": ["pci"],
        "coronary": ["pci"],
        "intervention": ["pci"]
    ]
    
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "as", "is", "are", "was", "were"
    ]
    
    /// Computes similarity score (0.0 to 1.0) using token overlap, Levenshtein distance, and medical synonyms
    static func similarity(spoken: String, expected: String) -> Double {
        let spoken = spoken.lowercased()
        let normalizedExpected = expected.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedExpected.isEmpty && spoken.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedExpected { return 1 }
        let spokenTokens = Set(spoken.components(separatedBy: CharacterSet.alphanumerics.inverted).map { $0.lowercased() }.filter { !$0.isEmpty && !stopWords.contains($0) })
        let expectedTokens = Set(expected.components(separatedBy: CharacterSet.alphanumerics.inverted).map { $0.lowercased() }.filter { !$0.isEmpty && !stopWords.contains($0) })
        
        guard !expectedTokens.isEmpty else { return 0.0 }
        
        var matches = 0.0
        for exp in expectedTokens {
            if spokenTokens.contains(exp) {
                matches += 1.0
                continue
            }
            
            // Check medical synonyms
            if let synonyms = medicalSynonyms[exp] {
                if synonyms.contains(where: { spokenTokens.contains($0) || spoken.contains($0) }) {
                    matches += 1.0
                    continue
                }
            }
            
            // Substring fuzzy matching
            if spokenTokens.contains(where: { token in
                guard token.count >= 5, exp.count >= 5 else { return false }
                return token.hasPrefix(exp) || exp.hasPrefix(token) || levenshteinDistance(token, exp) <= 1
            }) {
                matches += 0.8
            }
        }
        
        return min(1.0, matches / Double(expectedTokens.count))
    }
    
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }
        return dist[a.count][b.count]
    }
    
}
