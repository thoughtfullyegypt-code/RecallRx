import SwiftUI
import SwiftData

@main
@MainActor
struct RecallRxApp: App {
    let sharedModelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appTheme") private var appTheme = "system"

    init() {
        do {
            sharedModelContainer = try Self.makeModelContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// Hosted tests use a fresh memory-only container, including the fallback path.
    static func makeModelContainer(isStoredInMemoryOnly: Bool = AppRuntime.isTesting) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RecallRxSchemaV1.self)
        // Private CloudKit sync is managed explicitly. Automatic SwiftData mirroring
        // cannot represent this schema's non-optional relationships.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: RecallRxMigrationPlan.self, configurations: [configuration])
        } catch {
            let fallbackSchema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
            let fallback = ModelConfiguration(schema: fallbackSchema, isStoredInMemoryOnly: isStoredInMemoryOnly, cloudKitDatabase: .none)
            return try ModelContainer(for: fallbackSchema, configurations: [fallback])
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if AppRuntime.isTesting {
                    // Unit tests host the app without running UI tasks, onboarding, or lifecycle work.
                    Color.clear
                } else {
                    ContentView()
                        .task { LifecycleCoordinator.shared.start(context: sharedModelContainer.mainContext) }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active {
                                LifecycleCoordinator.shared.requestRefresh(context: sharedModelContainer.mainContext)
                            }
                        }
                }
            }
            .preferredColorScheme(colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
