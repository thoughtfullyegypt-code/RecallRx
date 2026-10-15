import SwiftUI
import SwiftData

@main
struct RecallRxApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: RecallRxSchemaV1.self)
        // CloudSyncManager talks to the private CloudKit database itself.
        // Leaving this on .automatic makes SwiftData mirror the store, and Core Data
        // then crashes (134060) because Deck.cards and Card.reviewLogs are not optional.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: RecallRxMigrationPlan.self, configurations: [modelConfiguration])
        } catch {
            do {
                let standardSchema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
                let fallback = ModelConfiguration(schema: standardSchema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
                return try ModelContainer(for: standardSchema, configurations: [fallback])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()
    
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
    
    var colorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
