import SwiftData
import XCTest
@testable import RecallRx

final class RecallRxTests: XCTestCase {
    @MainActor
    func testFeatureSuiteUsesAnInMemoryStore() throws {
        let schema = Schema(versionedSchema: RecallRxSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let report = TestRunner.shared.runAllTests(modelContext: container.mainContext)
        let failed = report.filter { !$0.passed }
        XCTAssertTrue(failed.isEmpty, failed.map { "\($0.name): \($0.details)" }.joined(separator: "\n"))
    }
}
