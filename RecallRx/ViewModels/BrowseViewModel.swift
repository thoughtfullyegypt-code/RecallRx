import Foundation
import SwiftData
import Observation

enum SortOrder: String, CaseIterable, Identifiable {
    case dateCreated
    case dateModified
    case dueDate
    case alphabetical
    case interval
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .dateCreated: return "Date Created"
        case .dateModified: return "Date Modified"
        case .dueDate: return "Due Date"
        case .alphabetical: return "Alphabetical"
        case .interval: return "Interval"
        }
    }
}

@Observable
final class BrowseViewModel {
    var modelContext: ModelContext
    var cards: [Card] = []
    
    // Search with 250ms debouncing
    var searchText: String = "" {
        didSet {
            debounceTask?.cancel()
            isSearching = true
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !Task.isCancelled {
                    debouncedSearchText = searchText
                    isSearching = false
                    currentPage = 1
                }
            }
        }
    }
    var debouncedSearchText: String = ""
    var isSearching: Bool = false
    private var debounceTask: Task<Void, Never>?
    
    func applySearchImmediate(query: String) {
        debounceTask?.cancel()
        searchText = query
        debouncedSearchText = query
        isSearching = false
        currentPage = 1
    }
    
    // Batch Pagination
    var pageSize: Int = 50
    var currentPage: Int = 1
    
    var selectedDeck: Deck? {
        didSet { currentPage = 1 }
    }
    var selectedTag: String? {
        didSet { currentPage = 1 }
    }
    var selectedState: CardState? {
        didSet { currentPage = 1 }
    }
    var sortOrder: SortOrder = .dateCreated {
        didSet { currentPage = 1 }
    }
    var sortAscending: Bool = false {
        didSet { currentPage = 1 }
    }
    var selectedCards: Set<UUID> = []
    var allTags: [String] = []
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchCards()
    }
    
    // MARK: - Fetching
    
    func fetchCards() {
        do {
            let descriptor = FetchDescriptor<Card>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            cards = try modelContext.fetch(descriptor)
            fetchAllTags()
        } catch {
            cards = []
        }
    }
    
    func fetchAllTags() {
        var tagSet = Set<String>()
        for card in cards {
            for tag in card.tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    tagSet.insert(trimmed)
                }
            }
        }
        if let storedTags = try? modelContext.fetch(FetchDescriptor<Tag>()) {
            for tag in storedTags {
                let trimmed = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    tagSet.insert(trimmed)
                }
            }
        }
        allTags = tagSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    // MARK: - Filtering & Sorting
    
    var filteredCards: [Card] {
        var result = cards
        
        // Filter by Deck
        if let selectedDeck = selectedDeck {
            result = result.filter { $0.deck?.id == selectedDeck.id }
        }
        
        // Filter by Tag
        if let selectedTag = selectedTag {
            result = result.filter { $0.tags.contains(selectedTag) }
        }
        
        // Filter by Card State
        if let selectedState = selectedState {
            result = result.filter { $0.state == selectedState }
        }
        
        // Filter by Search Query (using debounced query)
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { card in
                card.front.localizedCaseInsensitiveContains(query) ||
                card.back.localizedCaseInsensitiveContains(query) ||
                card.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        
        // Apply Sorting
        result.sort { first, second in
            let comparison: Bool
            switch sortOrder {
            case .dateCreated:
                comparison = first.createdAt < second.createdAt
            case .dateModified:
                comparison = first.modifiedAt < second.modifiedAt
            case .dueDate:
                comparison = first.dueDate < second.dueDate
            case .alphabetical:
                comparison = first.front.localizedCaseInsensitiveCompare(second.front) == .orderedAscending
            case .interval:
                comparison = first.interval < second.interval
            }
            return sortAscending ? comparison : !comparison
        }
        
        return result
    }
    
    // MARK: - Batch Pagination
    
    var displayedCards: [Card] {
        Array(filteredCards.prefix(currentPage * pageSize))
    }
    
    var hasMoreCards: Bool {
        displayedCards.count < filteredCards.count
    }
    
    func loadMoreCards() {
        if hasMoreCards {
            currentPage += 1
        }
    }
    
    // MARK: - Multi-select Operations
    
    func toggleSelectAll() {
        let visibleIDs = Set(filteredCards.map(\.id))
        if selectedCards.isSuperset(of: visibleIDs) && !visibleIDs.isEmpty {
            selectedCards.subtract(visibleIDs)
        } else {
            selectedCards.formUnion(visibleIDs)
        }
    }
    
    func deleteCards(_ cardIDs: Set<UUID>) {
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        for card in targetCards {
            modelContext.delete(card)
        }
        try? modelContext.save()
        selectedCards.subtract(cardIDs)
        fetchCards()
    }
    
    func moveCards(_ cardIDs: Set<UUID>, to deck: Deck) {
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        for card in targetCards {
            card.deck = deck
            card.modifiedAt = .now
        }
        try? modelContext.save()
        fetchCards()
    }
    
    func suspendCards(_ cardIDs: Set<UUID>) {
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        for card in targetCards {
            Scheduler.suspendCard(card)
        }
        try? modelContext.save()
        fetchCards()
    }
    
    func unsuspendCards(_ cardIDs: Set<UUID>) {
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        for card in targetCards {
            Scheduler.unsuspendCard(card)
        }
        try? modelContext.save()
        fetchCards()
    }
    
    func addTag(_ tag: String, to cardIDs: Set<UUID>) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        for card in targetCards {
            if !card.tags.contains(trimmed) {
                card.tags.append(trimmed)
                card.modifiedAt = .now
            }
        }
        
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmed })
        if let existing = try? modelContext.fetch(descriptor), existing.isEmpty {
            modelContext.insert(Tag(name: trimmed))
        }
        
        try? modelContext.save()
        fetchCards()
    }
    
    func removeTag(_ tag: String, from cardIDs: Set<UUID>) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        for card in targetCards {
            card.tags.removeAll { $0 == trimmed }
            card.modifiedAt = .now
        }
        
        try? modelContext.save()
        fetchCards()
    }
    
    func rescheduleCards(_ cardIDs: Set<UUID>, interval: Int) {
        let targetCards = cards.filter { cardIDs.contains($0.id) }
        let days = max(0, interval)
        for card in targetCards {
            card.interval = Double(days)
            card.repetitions = days > 0 ? max(1, card.repetitions) : 0
            card.state = days > 0 ? .review : .new
            card.dueDate = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
            card.modifiedAt = .now
        }
        try? modelContext.save()
        fetchCards()
    }
}
