import SwiftUI
import SwiftData

@main
struct AnkiApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: RecallRxSchemaV1.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, migrationPlan: RecallRxMigrationPlan.self, configurations: [modelConfiguration])
        } catch {
            do {
                let standardSchema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
                return try ModelContainer(for: standardSchema, configurations: [ModelConfiguration(schema: standardSchema, isStoredInMemoryOnly: false)])
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
