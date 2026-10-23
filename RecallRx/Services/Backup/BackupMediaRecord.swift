import Foundation

struct BackupMediaRecord: Codable, Equatable {
    let relativePath: String
    let data: Data
}
