import Foundation
import SwiftData

/// RecallRx SwiftData Versioned Schema Architecture
/// Defines formal database schemas and migration plans to guarantee backward compatibility
/// and ensure that future app updates never corrupt or delete user flashcards.

public enum RecallRxSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)
    
    public static var models: [any PersistentModel.Type] {
        [
            Deck.self,
            Card.self,
            ReviewLog.self,
            Tag.self
        ]
    }
}

/// Official Migration Plan for RecallRx
public enum RecallRxMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [RecallRxSchemaV1.self]
    }
    
    public static var stages: [MigrationStage] {
        // Version 1.0.0 initial release: no custom migration stages required yet
        []
    }
}
