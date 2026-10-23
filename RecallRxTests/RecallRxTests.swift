import Foundation
import SwiftData
import XCTest
@testable import RecallRx

final class RecallRxTests: XCTestCase {
    @MainActor
    func testFeatureSuiteUsesAnInMemoryStore() throws {
        let suiteName = "RecallRx.FeatureSuite.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecallRx-FeatureSuite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(true, forKey: "useFSRS")
        defaults.set(true, forKey: "enableLoadBalancer")

        let schema = Schema(versionedSchema: RecallRxSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let mediaDirectory = root.appendingPathComponent("Media", isDirectory: true)
        let runner = TestRunner(
            defaults: defaults,
            mediaManager: MediaManager(mediaDirectoryURL: mediaDirectory),
            backupManager: BackupManager(
                backupsDirectoryURL: root.appendingPathComponent("Backups", isDirectory: true),
                mediaDirectoryURL: mediaDirectory
            ),
            widgetManager: WidgetDataManager(defaults: defaults, sideEffectsEnabled: false),
            notificationManager: NotificationManager(defaults: defaults, sideEffectsEnabled: false),
            cloudSyncManager: CloudSyncManager(defaults: defaults)
        )
        let report = runner.runAllTests(modelContext: container.mainContext)
        XCTAssertFalse(report.isEmpty)
        let failed = report.filter { !$0.passed }
        XCTAssertTrue(failed.isEmpty, failed.map { "\($0.name): \($0.details)" }.joined(separator: "\n"))
    }

    func testGeneratedCardTelemetryUsesOnlyItsInjectedPreferences() throws {
        let suiteName = "RecallRx.TelemetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let standardGenerated = UserDefaults.standard.object(forKey: "telemetry_cards_generated") as? Int
        let standardApproved = UserDefaults.standard.object(forKey: "telemetry_cards_approved") as? Int
        let telemetry = PDFCardTelemetry(defaults: defaults)

        let cards = PDFCardGenerator.generateCards(
            fromPlainText: "Hypertrophic cardiomyopathy is defined as asymmetric septal hypertrophy.",
            telemetry: telemetry
        )
        XCTAssertFalse(cards.isEmpty)
        telemetry.logApproved(count: 2)
        XCTAssertEqual(telemetry.stats.generated, cards.count)
        XCTAssertEqual(telemetry.stats.approved, 2)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "telemetry_cards_generated") as? Int, standardGenerated)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "telemetry_cards_approved") as? Int, standardApproved)
    }
}
