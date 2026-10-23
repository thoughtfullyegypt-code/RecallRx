import Foundation
import Combine
import UserNotifications
import SwiftData

/// Daily study reminders and badges; injectable preferences keep tests isolated.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager(defaults: AppRuntime.defaults())

    private let defaults: UserDefaults
    let sideEffectsEnabled: Bool
    private let reminderNotificationID = "recallrx_daily_study_reminder"

    @Published private(set) var isAuthorized = false
    @Published var dailyRemindersEnabled: Bool {
        didSet { defaults.set(dailyRemindersEnabled, forKey: "daily_reminders_enabled") }
    }
    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: "reminder_hour") }
    }
    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: "reminder_minute") }
    }

    init(defaults: UserDefaults, sideEffectsEnabled: Bool = true) {
        self.defaults = defaults
        self.sideEffectsEnabled = sideEffectsEnabled && !AppRuntime.isTesting
        dailyRemindersEnabled = defaults.bool(forKey: "daily_reminders_enabled")
        // Midnight is a valid saved value, not an absent preference.
        let savedHour = defaults.object(forKey: "reminder_hour") as? Int
        reminderHour = savedHour.map { min(max($0, 0), 23) } ?? 20
        reminderMinute = min(max(defaults.integer(forKey: "reminder_minute"), 0), 59)
    }

    func requestAuthorization() async -> Bool {
        guard sideEffectsEnabled else { return false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            print("[NotificationManager] Authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func checkAuthorizationStatus() async {
        guard sideEffectsEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Refreshes an existing opt-in reminder; app lifecycle never prompts for permission.
    func refreshDailyReminder(dueCount: Int, streakDays: Int) async {
        guard sideEffectsEnabled else { return }
        await checkAuthorizationStatus()
        scheduleDailyReminder(dueCount: dueCount, streakDays: streakDays)
    }

    func scheduleDailyReminder(dueCount: Int = 0, streakDays: Int = 0) {
        guard dailyRemindersEnabled else {
            cancelDailyReminder()
            return
        }
        guard sideEffectsEnabled, isAuthorized else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderNotificationID])
        let content = UNMutableNotificationContent()
        content.title = "RecallRx Study Reminder"
        content.body = Self.reminderBody(dueCount: dueCount, streakDays: streakDays)
        content.sound = .default
        var components = DateComponents()
        components.hour = min(max(reminderHour, 0), 23)
        components.minute = min(max(reminderMinute, 0), 59)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderNotificationID, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                print("[NotificationManager] Could not schedule reminder: \(error.localizedDescription)")
            }
        }
    }

    static func reminderBody(dueCount: Int, streakDays: Int) -> String {
        let due = max(dueCount, 0)
        if due > 0, streakDays > 0 {
            return "You have \(due) \(due == 1 ? "card" : "cards") ready to review. Continue your \(streakDays)-day study streak."
        }
        if due > 0 {
            return "You have \(due) \(due == 1 ? "card" : "cards") ready to review. Make room for a little recall today."
        }
        return "Time for your daily medical review. Open RecallRx to see what is ready."
    }

    func cancelDailyReminder() {
        guard sideEffectsEnabled else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderNotificationID])
    }

    func updateBadge(dueCount: Int) {
        guard sideEffectsEnabled else { return }
        UNUserNotificationCenter.current().setBadgeCount(max(dueCount, 0)) { error in
            if let error {
                print("[NotificationManager] Could not set badge: \(error.localizedDescription)")
            }
        }
    }
}
