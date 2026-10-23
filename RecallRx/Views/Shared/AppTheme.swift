import SwiftUI

/// Shared presentation tokens for the app's light and dark appearances.
enum AppTheme {
    static let accent = Color("AccentColor")
    static let onAccent = Color("OnAccent")
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let secondarySurface = Color("SecondarySurface")
    static let border = Color.primary.opacity(0.09)
    static let contentWidth: CGFloat = 760
    static let cornerRadius: CGFloat = 20

    static func controlTint(named name: String) -> Color {
        switch name {
        case "Blue": return .blue
        case "Indigo": return .indigo
        case "Purple": return .purple
        case "Orange": return .orange
        case "Green": return .green
        default: return accent
        }
    }
}
