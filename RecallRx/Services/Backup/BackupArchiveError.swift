import Foundation

enum BackupArchiveError: LocalizedError {
    case invalid(String)
    case unsupportedVersion(Int)
    case mediaRollbackFailed(original: Error, recovery: Error, recoveryDirectory: URL?)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason):
            return "The backup is invalid: \(reason)"
        case .unsupportedVersion(let version):
            return "Backup version \(version) is not supported by this version of RecallRx."
        case .mediaRollbackFailed(let original, let recovery, let directory):
            let location = directory.map { " Original media is retained at \($0.path)." } ?? ""
            return "Restore failed: \(original.localizedDescription). Media recovery also failed: \(recovery.localizedDescription).\(location)"
        }
    }
}
