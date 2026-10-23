import Foundation

enum CloudSyncError: LocalizedError {
    case unsavedChanges
    case invalidRecord(String)
    case missingCard(String)

    var errorDescription: String? {
        switch self {
        case .unsavedChanges:
            return "Save your current changes before applying iCloud updates."
        case .invalidRecord(let identifier):
            return "An iCloud record is incomplete (\(identifier)). Sync will retry without skipping it."
        case .missingCard(let identifier):
            return "Review history is waiting for its card (\(identifier)). Sync will retry without skipping it."
        }
    }
}
