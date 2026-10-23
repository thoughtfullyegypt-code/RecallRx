import Foundation

/// Voice Command Types Recognized in Driving Mode
enum DrivingVoiceCommand: String, CaseIterable, Sendable {
    case repeatQuestion = "repeat"
    case skipCard = "skip"
    case requestHint = "hint"
    case stopSession = "stop"
}

