import Foundation

/// Search Syntax & Advanced Query Engine for RecallRx
/// Parses Anki-compatible search tokens such as `tag:`, `is:due`, `is:new`, `deck:`, `is:suspended`
final class SearchSyntaxParser {
    
    struct ParsedQuery {
        var tags: [String] = []
        var excludedTags: [String] = []
        var states: [CardState] = []
        var isDue: Bool? = nil
        var isSuspended: Bool? = nil
        var isBuried: Bool? = nil
        var isFlagged: Bool? = nil
        var deckName: String? = nil
        var textTerms: [String] = []
    }
    
    /// Parses an input search string into structured query tokens
    static func parse(_ query: String) -> ParsedQuery {
        var parsed = ParsedQuery()
        let tokens = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        for token in tokens {
            let lower = token.lowercased()
            
            if lower.hasPrefix("tag:") {
                let tagValue = String(token.dropFirst(4))
                parsed.tags.append(tagValue)
            } else if lower.hasPrefix("-tag:") {
                let tagValue = String(token.dropFirst(5))
                parsed.excludedTags.append(tagValue)
            } else if lower.hasPrefix("deck:") {
                let deckValue = String(token.dropFirst(5)).replacingOccurrences(of: "\"", with: "")
                parsed.deckName = deckValue
            } else if lower == "is:due" {
                parsed.isDue = true
            } else if lower == "is:new" {
                parsed.states.append(.new)
            } else if lower == "is:learning" {
                parsed.states.append(.learning)
            } else if lower == "is:review" {
                parsed.states.append(.review)
            } else if lower == "is:suspended" {
                parsed.isSuspended = true
            } else if lower == "-is:suspended" {
                parsed.isSuspended = false
            } else if lower == "is:buried" {
                parsed.isBuried = true
            } else if lower == "is:flagged" {
                parsed.isFlagged = true
            } else {
                parsed.textTerms.append(token)
            }
        }
        
        return parsed
    }
    
    /// Filters a list of cards against the search syntax query
    static func filter(cards: [Card], query: String, referenceDate: Date = Date()) -> [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cards }
        
        let parsed = parse(trimmed)
        
        return cards.filter { card in
            // 1. Tag filters
            for tag in parsed.tags {
                if !card.tags.contains(where: { $0.localizedCaseInsensitiveContains(tag) }) {
                    return false
                }
            }
            for excluded in parsed.excludedTags {
                if card.tags.contains(where: { $0.localizedCaseInsensitiveContains(excluded) }) {
                    return false
                }
            }
            
            // 2. Deck filter
            if let targetDeck = parsed.deckName {
                guard let deck = card.deck, deck.name.localizedCaseInsensitiveContains(targetDeck) else {
                    return false
                }
            }
            
            // 3. State filter
            if !parsed.states.isEmpty {
                if !parsed.states.contains(card.state) {
                    return false
                }
            }
            
            // 4. Due filter
            if let isDue = parsed.isDue, isDue {
                if card.state == .new || card.dueDate > referenceDate || card.isSuspended || card.isBuried {
                    return false
                }
            }
            
            // 5. Suspended / Buried
            if let isSuspended = parsed.isSuspended {
                if card.isSuspended != isSuspended { return false }
            }
            if let isBuried = parsed.isBuried {
                if card.isBuried != isBuried { return false }
            }
            
            // 6. Text terms matching front, back, extra, or clinical pearls
            for term in parsed.textTerms {
                let match = card.front.localizedCaseInsensitiveContains(term)
                    || card.back.localizedCaseInsensitiveContains(term)
                    || card.extra.localizedCaseInsensitiveContains(term)
                    || card.clinicalPearls.localizedCaseInsensitiveContains(term)
                    || card.firstAid.localizedCaseInsensitiveContains(term)
                if !match {
                    return false
                }
            }
            
            return true
        }
    }
}
