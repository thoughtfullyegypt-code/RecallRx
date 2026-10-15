import SwiftUI

// MARK: - Date Extensions

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }
    
    func daysFrom(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date.startOfDay, to: self.startOfDay).day ?? 0
    }
    
    func addingDays(_ days: Double) -> Date {
        self.addingTimeInterval(days * 86400)
    }
    
    func addingMinutes(_ minutes: Double) -> Date {
        self.addingTimeInterval(minutes * 60)
    }
    
    var relativeDescription: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: self)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        
        if days == 0 {
            return "Today"
        } else if days == -1 {
            return "Yesterday"
        } else if days < -1 {
            return "\(abs(days)) days ago"
        } else if days == 1 {
            return "In 1 day"
        } else {
            return "In \(days) days"
        }
    }
    
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    var shortDescription: String {
        Self.shortDateFormatter.string(from: self)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    var formattedStudyTime: String {
        let totalSeconds = max(0, Int(self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            if seconds > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "\(minutes)m"
            }
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - String Extensions

extension String {
    var truncated50: String {
        if count > 50 {
            return String(prefix(47)) + "..."
        }
        return self
    }
    
    func removingHTMLTags() -> String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Color Extensions

extension Color {
    static let ankiBlue = Color.blue
    static let ankiGreen = Color.green
    static let ankiRed = Color.red
    static let ankiOrange = Color.orange
    static let ankiNew = Color.blue
    static let ankiLearning = Color.orange
    static let ankiReview = Color.green
    static let ankiMature = Color(red: 0.0, green: 0.5, blue: 0.0)
}
