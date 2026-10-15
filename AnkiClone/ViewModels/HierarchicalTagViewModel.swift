import Foundation
import SwiftData
import SwiftUI

final class TagTreeNode: Identifiable, ObservableObject {
    let id: String
    let name: String
    let fullPath: String
    var children: [TagTreeNode] = []
    var cardIDs: Set<UUID> = []
    
    // Aggregated counts including all children
    var totalCardsCount: Int = 0
    var suspendedCardsCount: Int = 0
    
    init(name: String, fullPath: String) {
        self.id = fullPath
        self.name = name
        self.fullPath = fullPath
    }
}

@Observable
final class HierarchicalTagViewModel {
    var modelContext: ModelContext
    var rootNodes: [TagTreeNode] = []
    var searchText: String = ""
    var expandedNodeIDs: Set<String> = []
    var allCards: [Card] = []
    var lastActionMessage: String? = nil
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchAndBuildTree()
    }
    
    func fetchAndBuildTree() {
        let descriptor = FetchDescriptor<Card>()
        allCards = (try? modelContext.fetch(descriptor)) ?? []
        buildTree()
    }
    
    private func buildTree() {
        // Build a trie of nodes
        var nodeMap: [String: TagTreeNode] = [:]
        
        for card in allCards {
            for tag in card.tags {
                let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanTag.isEmpty else { continue }
                
                // Split by "::"
                let components = cleanTag.components(separatedBy: "::")
                var currentPath = ""
                
                for i in 0..<components.count {
                    let part = components[i]
                    let previousPath = currentPath
                    currentPath = currentPath.isEmpty ? part : "\(currentPath)::\(part)"
                    
                    if nodeMap[currentPath] == nil {
                        nodeMap[currentPath] = TagTreeNode(name: part, fullPath: currentPath)
                    }
                    
                    if !previousPath.isEmpty, let parent = nodeMap[previousPath], let child = nodeMap[currentPath] {
                        if !parent.children.contains(where: { $0.id == child.id }) {
                            parent.children.append(child)
                        }
                    }
                    
                    // Add card to this node and all ancestors
                    nodeMap[currentPath]?.cardIDs.insert(card.id)
                }
            }
        }
        
        // Root nodes are those whose fullPath has no "::"
        var roots: [TagTreeNode] = []
        for (path, node) in nodeMap {
            if !path.contains("::") {
                roots.append(node)
            }
        }
        
        // Sort children recursively
        func sortAndAggregate(node: TagTreeNode) {
            node.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            
            // Calculate suspended and total cards
            let nodeCards = allCards.filter { node.cardIDs.contains($0.id) }
            node.totalCardsCount = nodeCards.count
            node.suspendedCardsCount = nodeCards.filter { $0.isSuspended }.count
            
            for child in node.children {
                sortAndAggregate(node: child)
            }
        }
        
        roots.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for r in roots {
            sortAndAggregate(node: r)
        }
        
        self.rootNodes = roots
    }
    
    // MARK: - Filtered Nodes
    var filteredRoots: [TagTreeNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rootNodes }
        
        func matchesSearch(node: TagTreeNode) -> Bool {
            if node.name.lowercased().contains(query) || node.fullPath.lowercased().contains(query) {
                return true
            }
            return node.children.contains(where: { matchesSearch(node: $0) })
        }
        
        return rootNodes.filter { matchesSearch(node: $0) }
    }
    
    // MARK: - Node Card Retrieval
    func getCards(for node: TagTreeNode) -> [Card] {
        allCards.filter { node.cardIDs.contains($0.id) }
    }
    
    // MARK: - Bulk Actions on Tag Branch
    func unsuspendNode(_ node: TagTreeNode) {
        let cards = getCards(for: node)
        for card in cards {
            card.isSuspended = false
            card.modifiedAt = Date()
        }
        try? modelContext.save()
        lastActionMessage = "Unsuspended \(cards.count) cards in '\(node.name)'"
        fetchAndBuildTree()
    }
    
    func suspendNode(_ node: TagTreeNode) {
        let cards = getCards(for: node)
        for card in cards {
            card.isSuspended = true
            card.modifiedAt = Date()
        }
        try? modelContext.save()
        lastActionMessage = "Suspended \(cards.count) cards in '\(node.name)'"
        fetchAndBuildTree()
    }
    
    func createCramDeck(for node: TagTreeNode) -> Deck? {
        let cards = getCards(for: node)
        guard !cards.isEmpty else { return nil }
        
        let deckName = "\(node.name) Cram"
        let cramDeck = Deck(
            name: deckName,
            descriptionText: "Topic cram session from tag #\(node.fullPath)",
            newCardsPerDay: 9999,
            reviewsPerDay: 9999
        )
        modelContext.insert(cramDeck)
        
        let now = Date()
        for card in cards {
            card.isSuspended = false
            card.isBuried = false
            card.dueDate = now
            card.deck = cramDeck
            card.modifiedAt = now
        }
        
        try? modelContext.save()
        lastActionMessage = "Created cram deck '\(deckName)' with \(cards.count) cards!"
        return cramDeck
    }
}
