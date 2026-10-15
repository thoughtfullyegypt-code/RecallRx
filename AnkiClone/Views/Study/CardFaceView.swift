import SwiftUI

enum MedicalSection: String, CaseIterable, Identifiable {
    case extra = "Extra"
    case firstAid = "First Aid"
    case sketchy = "Sketchy"
    case pathoma = "Pathoma"
    case pearls = "Pearls"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .extra: return "doc.text.fill"
        case .firstAid: return "cross.fill"
        case .sketchy: return "paintpalette.fill"
        case .pathoma: return "microscope.fill"
        case .pearls: return "lightbulb.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .extra: return .indigo
        case .firstAid: return .blue
        case .sketchy: return .orange
        case .pathoma: return .purple
        case .pearls: return .yellow
        }
    }
}

struct CardFaceView: View {
    let content: String
    let isFront: Bool
    let noteType: NoteType
    var card: Card? = nil
    
    // Feature 4: Interactive One-by-One Cloze Revealing
    @State private var revealedClozeIndices: Set<Int> = []
    
    // Feature 2: Collapsible Medical Resource Sections
    @State private var expandedSections: Set<MedicalSection> = []
    
    init(content: String, isFront: Bool, noteType: NoteType, card: Card? = nil) {
        self.content = content
        self.isFront = isFront
        self.noteType = noteType
        self.card = card
    }
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                // Interactive Cloze helper bar (if multiple clozes and on front)
                if isFront && isClozeType && clozeMatchesCount > 1 {
                    clozeOneByOneBar
                }
                
                Spacer(minLength: 16)
                
                // Main Question/Answer Prompt
                renderedPromptView
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Feature 2: Collapsible Medical Resource Sections (on Back)
                if !isFront, let card = card, card.hasMedicalResources {
                    medicalResourcesView(card: card)
                }
                
                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    private var isClozeType: Bool {
        noteType == .cloze || noteType == .medical
    }
    
    private var isImageOcclusionType: Bool {
        noteType == .imageOcclusion
    }
    
    // MARK: - Prompt Rendering with Interactive Cloze, HTML & Image Occlusion
    @ViewBuilder
    private var renderedPromptView: some View {
        if isImageOcclusionType {
            imageOcclusionView
        } else {
            RichTextHTMLView(
                rawContent: sanitizedContent,
                isFront: isFront,
                noteType: noteType,
                targetClozeIndex: 1,
                revealedClozeIndices: revealedClozeIndices,
                onToggleCloze: { idx in
                    if revealedClozeIndices.contains(idx) {
                        revealedClozeIndices.remove(idx)
                    } else {
                        revealedClozeIndices.insert(idx)
                    }
                }
            )
        }
    }
    
    // MARK: - Image Occlusion Renderer
    @ViewBuilder
    private var imageOcclusionView: some View {
        let payload = ImageOcclusionPayload.from(json: sanitizedContent) ?? (card != nil ? ImageOcclusionPayload.from(json: card!.front) : nil)
        if let p = payload {
            VStack(spacing: 12) {
                Text(p.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                
                ZStack {
                    MedicalDiagramCanvasView(diagramId: p.diagramId)
                        .frame(maxWidth: .infinity)
                    
                    GeometryReader { geo in
                        ForEach(p.masks) { mask in
                            let isActive = mask.id == p.activeMaskId
                            let shouldHide = isActive ? isFront : (p.mode == .hideAllGuessOne)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        isActive
                                            ? (isFront ? Color.orange : Color.green)
                                            : (shouldHide ? Color.blue.opacity(0.8) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(isActive ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .shadow(color: Color.black.opacity(isActive ? 0.3 : 0.1), radius: isActive ? 4 : 1)
                                
                                if isActive && isFront {
                                    Text("?")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundColor(.white)
                                } else if isActive && !isFront {
                                    Text(mask.label)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .padding(.horizontal, 4)
                                } else if shouldHide {
                                    Text("[\(mask.id)]")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .frame(
                                width: max(30, geo.size.width * mask.width),
                                height: max(20, geo.size.height * mask.height)
                            )
                            .position(
                                x: geo.size.width * (mask.x + mask.width / 2.0),
                                y: geo.size.height * (mask.y + mask.height / 2.0)
                            )
                        }
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if !isFront, let activeMask = p.masks.first(where: { $0.id == p.activeMaskId }) {
                    VStack(spacing: 4) {
                        Text(activeMask.label)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.primary)
                        
                        if let hint = activeMask.hint, !hint.isEmpty {
                            Text(hint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } else {
            Text(sanitizedContent)
                .font(.headline)
        }
    }
    
    // MARK: - Interactive Cloze Engine
    private struct ParsedCloze: Identifiable {
        let id: Int
        let fullRange: Range<String.Index>
        let answer: String
        let hint: String?
    }
    
    private var parsedClozeItems: [ParsedCloze] {
        let raw = sanitizedContent
        guard let regex = try? NSRegularExpression(pattern: #"\{\{c(\d+)::(.*?)\}\}"#, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(raw.startIndex..., in: raw)
        let matches = regex.matches(in: raw, options: [], range: nsRange)
        
        var list: [ParsedCloze] = []
        for match in matches {
            guard let fullRange = Range(match.range, in: raw),
                  let idxRange = Range(match.range(at: 1), in: raw),
                  let contentRange = Range(match.range(at: 2), in: raw),
                  let clozeIndex = Int(raw[idxRange]) else { continue }
            
            let matchedContent = String(raw[contentRange])
            let answer: String
            let hint: String?
            if let colonRange = matchedContent.range(of: "::") {
                answer = String(matchedContent[..<colonRange.lowerBound])
                let rawHint = String(matchedContent[colonRange.upperBound...])
                hint = rawHint.isEmpty ? nil : rawHint
            } else {
                answer = matchedContent
                hint = nil
            }
            list.append(ParsedCloze(id: clozeIndex, fullRange: fullRange, answer: answer, hint: hint))
        }
        return list
    }
    
    private var clozeMatchesCount: Int {
        parsedClozeItems.count
    }
    
    // Feature 4: Interactive One-by-One Toolbar
    private var clozeOneByOneBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.caption2)
                .foregroundColor(.blue)
            Text("Tap [...] to reveal individually")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !revealedClozeIndices.isEmpty {
                Button("Hide All") {
                    withAnimation(.spring(response: 0.3)) {
                        revealedClozeIndices.removeAll()
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundColor(.red)
            }
            
            Button("Reveal All") {
                withAnimation(.spring(response: 0.3)) {
                    for item in parsedClozeItems {
                        revealedClozeIndices.insert(item.id)
                    }
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.blue.opacity(0.08)))
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var interactiveClozeView: some View {
        // Build view with tappable clozes
        let clozes = parsedClozeItems
        if clozes.isEmpty {
            Text(sanitizedContent)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .lineSpacing(6)
        } else {
            clozeTextWithTaps
        }
    }
    
    private var clozeTextWithTaps: some View {
        let raw = sanitizedContent
        let clozes = parsedClozeItems
        
        var result = AttributedString()
        var currentIndex = raw.startIndex
        
        for item in clozes {
            if currentIndex < item.fullRange.lowerBound {
                let text = String(raw[currentIndex..<item.fullRange.lowerBound])
                result.append(AttributedString(text))
            }
            
            let isRevealed = !isFront || revealedClozeIndices.contains(item.id)
            if isRevealed {
                var attr = AttributedString(" \(item.answer) ")
                attr.foregroundColor = isFront ? .teal : .blue
                attr.font = .system(size: 22, weight: .bold, design: .serif)
                attr.underlineStyle = .single
                attr.backgroundColor = (isFront ? Color.teal : Color.blue).opacity(0.12)
                result.append(attr)
            } else {
                let label = (item.hint != nil && !item.hint!.isEmpty) ? "[\(item.hint!)]" : "[...]"
                var attr = AttributedString(" \(label) ")
                attr.foregroundColor = .blue
                attr.font = .system(size: 22, weight: .bold, design: .rounded)
                attr.backgroundColor = Color.blue.opacity(0.12)
                result.append(attr)
            }
            currentIndex = item.fullRange.upperBound
        }
        
        if currentIndex < raw.endIndex {
            result.append(AttributedString(String(raw[currentIndex...])))
        }
        
        return Text(result)
            .font(.system(size: 22, weight: .regular, design: .serif))
            .lineSpacing(6)
            .contentShape(Rectangle())
            .onTapGesture {
                // Tapping reveals the next unrevealed cloze in order!
                if isFront {
                    if let nextUnrevealed = clozes.first(where: { !revealedClozeIndices.contains($0.id) }) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            revealedClozeIndices.insert(nextUnrevealed.id)
                        }
                    }
                }
            }
    }
    
    // MARK: - Feature 2: High-Yield Medical Resource Sections
    @ViewBuilder
    private func medicalResourcesView(card: Card) -> some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 20)
            
            // Available Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !card.extra.isEmpty {
                        sectionPill(.extra, card: card)
                    }
                    if !card.firstAid.isEmpty {
                        sectionPill(.firstAid, card: card)
                    }
                    if !card.sketchy.isEmpty {
                        sectionPill(.sketchy, card: card)
                    }
                    if !card.pathoma.isEmpty {
                        sectionPill(.pathoma, card: card)
                    }
                    if !card.clinicalPearls.isEmpty {
                        sectionPill(.pearls, card: card)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Expanded Content Accordions
            VStack(spacing: 10) {
                if expandedSections.contains(.extra) && !card.extra.isEmpty {
                    expandedSectionBox(.extra, text: card.extra)
                }
                if expandedSections.contains(.firstAid) && !card.firstAid.isEmpty {
                    expandedSectionBox(.firstAid, text: card.firstAid)
                }
                if expandedSections.contains(.sketchy) && !card.sketchy.isEmpty {
                    expandedSectionBox(.sketchy, text: card.sketchy)
                }
                if expandedSections.contains(.pathoma) && !card.pathoma.isEmpty {
                    expandedSectionBox(.pathoma, text: card.pathoma)
                }
                if expandedSections.contains(.pearls) && !card.clinicalPearls.isEmpty {
                    expandedSectionBox(.pearls, text: card.clinicalPearls)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    @ViewBuilder
    private func sectionPill(_ section: MedicalSection, card: Card) -> some View {
        let isExpanded = expandedSections.contains(section)
        
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                if isExpanded {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: section.icon)
                    .font(.caption2)
                Text(section.rawValue)
                    .font(.caption.weight(.semibold))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isExpanded ? section.color : section.color.opacity(0.12))
            .foregroundColor(isExpanded ? .white : section.color)
            .clipShape(Capsule())
            .shadow(color: isExpanded ? section.color.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func expandedSectionBox(_ section: MedicalSection, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(section.rawValue, systemImage: section.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(section.color)
                Spacer()
                Button {
                    withAnimation {
                        expandedSections.remove(section)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let markdown = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(markdown)
                    .font(.callout)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.callout)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(section.color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(section.color.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(12)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        ))
    }
    
    private var sanitizedContent: String {
        content
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
    }
}
