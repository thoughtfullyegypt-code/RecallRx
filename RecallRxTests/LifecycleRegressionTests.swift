import Foundation
import SwiftData
import XCTest
@testable import RecallRx

final class LifecycleRegressionTests: XCTestCase {
    func testRuntimeRequiresAnExplicitDebugAutomationFlag() {
        XCTAssertFalse(AppRuntime.isTesting(environment: [:]))
        XCTAssertTrue(AppRuntime.isTesting(environment: ["RECALLRX_TESTING": "1"]))
        XCTAssertTrue(AppRuntime.isTesting(environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]))
        XCTAssertFalse(AppRuntime.isUIAutomationEnabled(arguments: ["RecallRx"], environment: [:]))
        XCTAssertFalse(AppRuntime.isUIAutomationEnabled(arguments: ["RecallRx", "--enable-ui-automation"], environment: ["RECALLRX_TESTING": "1"]))
        #if DEBUG
        XCTAssertTrue(AppRuntime.isUIAutomationEnabled(arguments: ["RecallRx", "--enable-ui-automation"], environment: [:]))
        #else
        XCTAssertFalse(AppRuntime.isUIAutomationEnabled(arguments: ["RecallRx", "--enable-ui-automation"], environment: [:]))
        #endif
    }

    @MainActor
    func testHostedAppStartsWithAnEmptyMemoryOnlyLibrary() throws {
        XCTAssertTrue(AppRuntime.isTesting, "The test scheme must isolate its hosted app.")
        let container = try RecallRxApp.makeModelContainer()
        XCTAssertTrue(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Deck>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Card>()), 0)
    }

    @MainActor
    func testExplicitExamplesPreserveUserDeckNamesAndLoadOnlyOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let names = ["Test Deck", "Test Parent", "Validation Test Deck", "USMLE Step 1 & 2 High-Yield"]
        let userDecks = names.map { Deck(name: $0) }
        for deck in userDecks { context.insert(deck) }
        try context.save()

        SampleMedicalData.loadSampleMedicalDeck(into: context)
        let firstLoad = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(firstLoad.count, userDecks.count + 1)
        for deck in userDecks {
            XCTAssertTrue(firstLoad.contains { $0.id == deck.id })
            XCTAssertTrue(deck.cards.isEmpty, "Examples must not be injected into a user's same-named deck.")
        }
        SampleMedicalData.loadSampleMedicalDeck(into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Deck>()), firstLoad.count)
        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.allSatisfy { $0.fsrsReps == 0 && $0.reviewLogs.isEmpty })
    }

    @MainActor
    func testWidgetStartsAtZeroAndUsesActualBudgetedStudyQueues() throws {
        let suiteName = "RecallRx.WidgetRegression.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let untouched = UserDefaults.standard.data(forKey: "recallrx_widget_data")
        let manager = WidgetDataManager(defaults: defaults, sideEffectsEnabled: false)
        XCTAssertEqual(manager.getWidgetData().totalDue, 0)
        XCTAssertEqual(manager.getWidgetData().streakDays, 0)
        XCTAssertEqual(manager.getWidgetData().topDeckName, "")

        let container = try makeContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deck = Deck(name: "Cardiology", newCardsPerDay: 1, reviewsPerDay: 0)
        context.insert(deck)
        let cards = [
            Card(front: "First", deck: deck), Card(front: "Second", deck: deck),
            Card(front: "Learning", deck: deck, dueDate: now.addingTimeInterval(-60), stateRaw: CardState.learning.rawValue),
            Card(front: "Suspended", deck: deck, isSuspended: true),
            Card(front: "Future", deck: deck, dueDate: now.addingTimeInterval(3600), stateRaw: CardState.review.rawValue)
        ]
        for card in cards { context.insert(card) }
        deck.cards = cards
        try context.save()
        let snapshot = manager.updateWidgetData(context: context, now: now)
        XCTAssertEqual(snapshot.newCount, 1)
        XCTAssertEqual(snapshot.learnCount, 1)
        XCTAssertEqual(snapshot.reviewCount, 0)
        XCTAssertEqual(snapshot.totalDue, Scheduler.getDueCards(from: deck, now: now).count)
        XCTAssertEqual(snapshot.topDeckName, "Cardiology")
        XCTAssertEqual(manager.getWidgetData(), snapshot)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "recallrx_widget_data"), untouched)
        XCTAssertFalse(manager.sideEffectsEnabled)
    }

    @MainActor
    func testReminderSettingsPreserveMidnightAndAvoidSharedPreferences() async throws {
        let suiteName = "RecallRx.ReminderRegression.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let untouchedHour = UserDefaults.standard.object(forKey: "reminder_hour") as? Int
        defaults.set(0, forKey: "reminder_hour")
        defaults.set(15, forKey: "reminder_minute")
        defaults.set(true, forKey: "daily_reminders_enabled")
        let manager = NotificationManager(defaults: defaults, sideEffectsEnabled: false)
        XCTAssertEqual(manager.reminderHour, 0)
        XCTAssertEqual(manager.reminderMinute, 15)
        XCTAssertFalse(manager.sideEffectsEnabled)
        let granted = await manager.requestAuthorization()
        XCTAssertFalse(granted)
        manager.scheduleDailyReminder(dueCount: 3, streakDays: 0)
        manager.dailyRemindersEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "daily_reminders_enabled"))
        XCTAssertEqual(UserDefaults.standard.object(forKey: "reminder_hour") as? Int, untouchedHour)
        XCTAssertFalse(NotificationManager.reminderBody(dueCount: 3, streakDays: 0).contains("0-day"))
        XCTAssertTrue(NotificationManager.reminderBody(dueCount: 1, streakDays: 2).contains("1 card ready"))
    }

    @MainActor
    func testDeckDefaultsAndNestedIndependentBudgets() throws {
        let suiteName = "RecallRx.DeckDefaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(3, forKey: "defaultNewCardsPerDay")
        defaults.set(7, forKey: "defaultMaxReviewsPerDay")
        let container = try makeContainer()
        let context = container.mainContext
        let vm = DeckViewModel(modelContext: context, defaults: defaults)
        vm.addDeck(name: "Test Deck: real user title")
        let parent = try XCTUnwrap(vm.decks.first)
        XCTAssertEqual(parent.newCardsPerDay, 3)
        XCTAssertEqual(parent.reviewsPerDay, 7)
        XCTAssertTrue(vm.topLevelDecks.contains { $0.id == parent.id })
        parent.newCardsPerDay = 0
        vm.addDeck(name: "Child", parentDeckID: parent.id, newCardsPerDay: 1, reviewsPerDay: 0)
        let child = try XCTUnwrap(vm.decks.first { $0.parentDeckID == parent.id })
        let card = Card(front: "Child question", deck: child)
        context.insert(card)
        child.cards = [card]
        try context.save()
        XCTAssertEqual(vm.getDueCount(for: parent).new, 1, "A parent's exhausted budget must not cap a child's independent budget.")
        vm.addDeck(name: "Explicit zero", newCardsPerDay: -1, reviewsPerDay: 0)
        let zero = try XCTUnwrap(vm.decks.first { $0.name == "Explicit zero" })
        XCTAssertEqual(zero.newCardsPerDay, 0)
        XCTAssertEqual(zero.reviewsPerDay, 0)
    }

    @MainActor
    func testDisabledLifecycleNeverRunsServicesOrObservesSaves() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var calls = 0
        let coordinator = LifecycleCoordinator(
            isEnabled: false, debounceNanoseconds: 1_000_000,
            widgetRefresh: { _ in calls += 1; return .empty },
            reminderRefresh: { _ in calls += 1 }, automaticBackup: { _ in calls += 1 },
            captureLocalDeletions: { _ in calls += 1 }, markRestoredLibrary: { _ in calls += 1 }
        )
        coordinator.start(context: context)
        context.insert(Deck(name: "Saved in memory"))
        try context.save()
        coordinator.requestRefresh(context: context)
        await coordinator.refresh(context: context)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(calls, 0)
        coordinator.stop()
    }

    @MainActor
    func testSuccessfulSaveBurstCoalescesAndRestoreMarksBeforeRefresh() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        var widgetCalls = 0
        var backupCalls = 0
        var reminderCalls = 0
        var captureCalls = 0
        var restoredCalls = 0
        let refreshed = expectation(description: "Successful saves update derived data")
        var expectingSaveRefresh = false
        let coordinator = LifecycleCoordinator(
            isEnabled: true, debounceNanoseconds: 20_000_000,
            widgetRefresh: { _ in
                widgetCalls += 1
                if expectingSaveRefresh { refreshed.fulfill() }
                return .empty
            },
            reminderRefresh: { _ in reminderCalls += 1 },
            automaticBackup: { _ in backupCalls += 1 },
            captureLocalDeletions: { _ in captureCalls += 1 },
            markRestoredLibrary: { _ in restoredCalls += 1 }
        )
        defer { coordinator.stop() }
        coordinator.start(context: context)
        await coordinator.refresh(context: context)
        XCTAssertEqual(widgetCalls, 1)
        expectingSaveRefresh = true
        let deck = Deck(name: "Saved deck")
        context.insert(deck)
        try context.save()
        deck.descriptionText = "A second successful save in the same burst"
        try context.save()
        await fulfillment(of: [refreshed], timeout: 2)
        expectingSaveRefresh = false
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(widgetCalls, 2)
        XCTAssertEqual(backupCalls, 2)
        XCTAssertEqual(reminderCalls, 2)
        XCTAssertEqual(captureCalls, 2)

        NotificationCenter.default.post(name: BackupManager.didRestoreNotification, object: context)
        XCTAssertEqual(restoredCalls, 1, "Restored UUIDs must be marked synchronously before queued save/deletion capture.")
        await coordinator.refresh(context: context)
        XCTAssertEqual(captureCalls, 3)
        XCTAssertNil(coordinator.lastError)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Deck.self, Card.self, ReviewLog.self, Tag.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
