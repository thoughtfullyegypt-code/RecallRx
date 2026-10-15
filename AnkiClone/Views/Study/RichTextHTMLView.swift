import SwiftUI

/// Rich Text, HTML & Media Segment Model
enum CardSegment: Identifiable {
    case text(AttributedString)
    case cloze(index: Int, answer: String, hint: String?, isRevealed: Bool)
    case image(src: String)
    case audio(filename: String)
    
    var id: String {
        switch self {
        case .text(let str): return "text_\(str.hashValue)"
        case .cloze(let index, let answer, _, let isRevealed): return "cloze_\(index)_\(answer)_\(isRevealed)"
        case .image(let src): return "img_\(src)"
        case .audio(let filename): return "audio_\(filename)"
        }
    }
}

/// Rich Text & Media Renderer for RecallRx
/// Parses HTML tags, media images (<img src="...">), audio clips ([sound:...]), and Clozes ({{c1::...}})
struct RichTextHTMLView: View {
    let rawContent: String
    let isFront: Bool
    let noteType: NoteType
    var targetClozeIndex: Int = 1
    var revealedClozeIndices: Set<Int> = []
    var onToggleCloze: ((Int) -> Void)? = nil
    
    @ObservedObject private var mediaManager = MediaManager.shared
    @State private var selectedImageForZoom: UIImage? = nil
    
    var body: some View {
        let segments = parseSegments(from: rawContent)
        
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let attrString):
                    Text(attrString)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                case .cloze(let index, let answer, let hint, let isRevealed):
                    clozeView(index: index, answer: answer, hint: hint, isRevealed: isRevealed)
                    
                case .image(let src):
                    imageView(src: src)
                    
                case .audio(let filename):
                    audioButtonView(filename: filename)
                }
            }
        }
        .sheet(item: Binding<IdentifiableImage?>(
            get: { selectedImageForZoom.map { IdentifiableImage(image: $0) } },
            set: { selectedImageForZoom = $0?.image }
        )) { item in
            NavigationStack {
                ZoomableImageView(image: item.image)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                selectedImageForZoom = nil
                            }
                        }
                    }
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func clozeView(index: Int, answer: String, hint: String?, isRevealed: Bool) -> some View {
        if isFront && !isRevealed {
            Button {
                onToggleCloze?(index)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                    Text(hint ?? "[...]")
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            Text(answer)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .foregroundColor(.blue)
                .underline(color: .blue.opacity(0.6))
                .padding(.horizontal, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
        }
    }
    
    @ViewBuilder
    private func imageView(src: String) -> some View {
        if let fileURL = mediaManager.getMediaURL(for: src),
           let uiImage = UIImage(contentsOfFile: fileURL.path) {
            Button {
                selectedImageForZoom = uiImage
            } label: {
                VStack(spacing: 4) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
                        )
                    
                    HStack(spacing: 4) {
                        Image(systemName: "plus.magnifyingglass")
                        Text("Tap to Zoom")
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            // Placeholder / missing image indicator
            HStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundColor(.secondary)
                Text(src)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private func audioButtonView(filename: String) -> some View {
        let isPlaying = mediaManager.isPlayingAudio && mediaManager.currentPlayingAudioName == filename
        
        Button {
            if isPlaying {
                mediaManager.stopAudio()
            } else {
                mediaManager.playAudio(named: filename)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                    .foregroundColor(isPlaying ? .red : .blue)
                
                Text(isPlaying ? "Playing Audio..." : "Play Audio Clip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(filename)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isPlaying ? Color.red.opacity(0.1) : Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isPlaying ? Color.red.opacity(0.3) : Color.blue.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Parser
    
    private func parseSegments(from text: String) -> [CardSegment] {
        var segments: [CardSegment] = []
        
        // Normalize HTML break lines and carriage returns
        let prepared = text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<div>", with: "\n")
            .replacingOccurrences(of: "</div>", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        
        // Regex for media and cloze tokens:
        // 1. <img src="...">
        // 2. [sound:...]
        // 3. {{c1::...}}
        let combinedPattern = #"(<img[^>]+src=["']?([^"'>\s]+)["']?[^>]*>)|(\[sound:([^\]]+)\])|(\{\{c(\d+)::(.*?)(?:::(.*?))?\}\})"#
        guard let regex = try? NSRegularExpression(pattern: combinedPattern, options: .caseInsensitive) else {
            return [.text(formatHTMLString(prepared))]
        }
        
        let nsString = prepared as NSString
        var lastIndex = 0
        let matches = regex.matches(in: prepared, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            // Text preceding the match
            if match.range.location > lastIndex {
                let textChunk = nsString.substring(with: NSRange(location: lastIndex, length: match.range.location - lastIndex))
                let formatted = formatHTMLString(textChunk)
                if !formatted.characters.isEmpty {
                    segments.append(.text(formatted))
                }
            }
            
            // 1. Image match (<img src="...">)
            if match.range(at: 1).location != NSNotFound, match.range(at: 2).location != NSNotFound {
                let src = nsString.substring(with: match.range(at: 2))
                segments.append(.image(src: src))
            }
            // 2. Audio match ([sound:...])
            else if match.range(at: 3).location != NSNotFound, match.range(at: 4).location != NSNotFound {
                let filename = nsString.substring(with: match.range(at: 4))
                segments.append(.audio(filename: filename))
            }
            // 3. Cloze match ({{c1::answer::hint}})
            else if match.range(at: 5).location != NSNotFound {
                let indexStr = nsString.substring(with: match.range(at: 6))
                let index = Int(indexStr) ?? 1
                let answer = nsString.substring(with: match.range(at: 7))
                var hint: String? = nil
                if match.range(at: 8).location != NSNotFound {
                    hint = nsString.substring(with: match.range(at: 8))
                }
                
                let isRevealed = !isFront || revealedClozeIndices.contains(index) || (index != targetClozeIndex && !isFront)
                segments.append(.cloze(index: index, answer: answer, hint: hint, isRevealed: isRevealed))
            }
            
            lastIndex = match.range.location + match.range.length
        }
        
        // Remaining text trailing the last match
        if lastIndex < nsString.length {
            let trailing = nsString.substring(from: lastIndex)
            let formatted = formatHTMLString(trailing)
            if !formatted.characters.isEmpty {
                segments.append(.text(formatted))
            }
        }
        
        return segments.isEmpty ? [.text(formatHTMLString(prepared))] : segments
    }
    
    private func formatHTMLString(_ text: String) -> AttributedString {
        // Strip out unsupported complex HTML tags while preserving basic bold/italic/underline/color
        var clean = text
        
        // Remove style or script blocks if present
        clean = clean.replacingOccurrences(of: #"(?s)<style.*?</style>"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"(?s)<script.*?</script>"#, with: "", options: .regularExpression)
        
        // Convert simple HTML tags to markdown
        clean = clean.replacingOccurrences(of: "<b>", with: "**")
        clean = clean.replacingOccurrences(of: "</b>", with: "**")
        clean = clean.replacingOccurrences(of: "<strong>", with: "**")
        clean = clean.replacingOccurrences(of: "</strong>", with: "**")
        clean = clean.replacingOccurrences(of: "<i>", with: "*")
        clean = clean.replacingOccurrences(of: "</i>", with: "*")
        clean = clean.replacingOccurrences(of: "<em>", with: "*")
        clean = clean.replacingOccurrences(of: "</em>", with: "*")
        
        // Strip remaining unknown tags
        clean = clean.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        if let attr = try? AttributedString(markdown: clean, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(clean)
    }
}

// MARK: - Zoomable Image Preview Helper
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { _ in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(value, 4.0))
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                if scale < 1.0 { scale = 1.0 }
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9).ignoresSafeArea())
        }
    }
}
