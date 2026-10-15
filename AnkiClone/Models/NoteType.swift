import Foundation

enum NoteType: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic = "basic"
    case basicReversed = "basic_reversed"
    case cloze = "cloze"
    case medical = "medical"
    case imageOcclusion = "image_occlusion"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .basic:
            return "Basic"
        case .basicReversed:
            return "Basic (and reversed card)"
        case .cloze:
            return "Cloze"
        case .medical:
            return "USMLE Medical"
        case .imageOcclusion:
            return "Image Occlusion"
        }
    }
    
    var description: String {
        switch self {
        case .basic:
            return "Front and back card. Prompt on the front, answer on the back."
        case .basicReversed:
            return "Creates two cards: Front to Back, and Back to Front."
        case .cloze:
            return "Fill-in-the-blank style card using cloze deletions like {{c1::hidden text}}."
        case .medical:
            return "AnKing-style card with cloze prompt plus collapsible First Aid, Sketchy, Pathoma, and Pearls."
        case .imageOcclusion:
            return "Mask anatomical structures, histology slides, or pathways to test labels individually."
        }
    }
    
    var iconName: String {
        switch self {
        case .basic:
            return "rectangle.fill.on.rectangle.fill"
        case .basicReversed:
            return "arrow.left.arrow.right"
        case .cloze:
            return "character.cursor.ibeam"
        case .medical:
            return "stethoscope"
        case .imageOcclusion:
            return "photo.badge.plus"
        }
    }
}
