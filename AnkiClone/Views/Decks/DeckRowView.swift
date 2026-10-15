import SwiftUI

struct DeckRowView: View {
    let deck: Deck
    var newCount: Int? = nil
    var learningCount: Int? = nil
    var reviewCount: Int? = nil
    var indentationLevel: Int = 0
    var hasSubdecks: Bool = false
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)? = nil
    
    private var resolvedNew: Int {
        newCount ?? deck.newCards
    }
    
    private var resolvedLearning: Int {
        learningCount ?? deck.learningCards
    }
    
    private var resolvedReview: Int {
        reviewCount ?? deck.dueCards
    }
    
    var body: some View {
        HStack(spacing: 10) {
            if indentationLevel > 0 {
                Spacer()
                    .frame(width: CGFloat(indentationLevel) * 16)
            }
            
            if hasSubdecks {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onToggleExpand?()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 20, height: 20)
            }
            
            Image(systemName: "square.stack.fill")
                .font(.system(size: 16))
                .foregroundColor(.accentColor.opacity(0.85))
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.displayName)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                
                if !deck.descriptionText.isEmpty {
                    Text(deck.descriptionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                DeckCountBadge(count: resolvedNew, color: .blue)
                DeckCountBadge(count: resolvedLearning, color: .orange)
                DeckCountBadge(count: resolvedReview, color: .green)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct DeckCountBadge: View {
    let count: Int
    let color: Color
    
    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(count > 0 ? color : Color.secondary.opacity(0.4))
            .frame(minWidth: 26, minHeight: 20)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(count > 0 ? color.opacity(0.14) : Color(.systemGray5).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(count > 0 ? color.opacity(0.3) : Color.clear, lineWidth: 0.8)
            )
    }
}
