import Foundation

enum ImageOcclusionMode: String, Codable, Equatable {
    case hideAllGuessOne = "hide_all_guess_one"
    case hideOneGuessOne = "hide_one_guess_one"
}

struct ImageOcclusionMask: Codable, Identifiable, Equatable {
    var id: Int
    var label: String
    var x: Double       // 0.0 - 1.0 (relative to canvas width)
    var y: Double       // 0.0 - 1.0 (relative to canvas height)
    var width: Double   // 0.0 - 1.0 (relative to canvas width)
    var height: Double  // 0.0 - 1.0 (relative to canvas height)
    var hint: String?
}

struct ImageOcclusionPayload: Codable, Equatable {
    var diagramId: String
    var title: String
    var masks: [ImageOcclusionMask]
    var activeMaskId: Int
    var mode: ImageOcclusionMode
    var clinicalNotes: String
    
    func toJSON() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }
    
    static func from(json: String) -> ImageOcclusionPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ImageOcclusionPayload.self, from: data)
    }
    
    static func fromJSON(_ json: String) -> ImageOcclusionPayload? {
        return from(json: json)
    }
}
