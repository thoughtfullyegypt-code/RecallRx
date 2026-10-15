import Foundation
import UserNotifications
import SwiftData

/// Manages Local Notifications, Daily Study Reminders & App Icon Badges
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published private(set) var isAuthorized: Bool = false
    @Published var dailyRemindersEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(dailyRemindersEnabled, forKey: "daily_reminders_enabled")
        }
    }
    @Published var reminderHour: Int = 20 { // 8:00 PM default
        didSet {
            UserDefaults.standard.set(reminderHour, forKey: "reminder_hour")
        }
    }
    @Published var reminderMinute: Int = 0 {
        didSet {
            UserDefaults.standard.set(reminderMinute, forKey: "reminder_minute")
        }
    }
    
    private let reminderNotificationID = "recallrx_daily_study_reminder"
    
    private init() {
        self.dailyRemindersEnabled = UserDefaults.standard.bool(forKey: "daily_reminders_enabled")
        let savedHour = UserDefaults.standard.integer(forKey: "reminder_hour")
        self.reminderHour = savedHour > 0 ? savedHour : 20
        self.reminderMinute = UserDefaults.standard.integer(forKey: "reminder_minute")
        
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    /// Requests notification permissions for alerts, sounds, and badges
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            self.isAuthorized = granted
            return granted
        } catch {
            print("[NotificationManager] Error requesting authorization: \(error.localizedDescription)")
            self.isAuthorized = false
            return false
        }
    }
    
    /// Checks current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
    }
    
    /// Schedules or updates the daily study reminder
    func scheduleDailyReminder(dueCount: Int = 0, streakDays: Int = 0) {
        guard dailyRemindersEnabled else {
            cancelDailyReminder()
            return
        }
        
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderNotificationID])
        
        let content = UNMutableNotificationContent()
        content.title = "RecallRx Study Reminder"
        
        if dueCount > 0 {
            content.body = "You have \(dueCount) cards due today. Keep your \(streakDays)-day study streak alive!"
        } else {
            content.body = "Time for your daily medical review. Keep your knowledge sharp for exams!"
        }
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: reminderNotificationID, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("[NotificationManager] Error scheduling reminder: \(error.localizedDescription)")
            }
        }
    }
    
    /// Cancels the scheduled daily study reminder
    func cancelDailyReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderNotificationID])
    }
    
    /// Updates the application badge with the number of due cards
    func updateBadge(dueCount: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(dueCount) { error in
                if let error = error {
                    print("[NotificationManager] Error setting badge count: \(error.localizedDescription)")
                }
            }
        }
    }
}
