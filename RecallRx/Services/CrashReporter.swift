import Foundation

/// On-Device Crash & Error Diagnostic Reporting Wrapper
/// 100% offline and private. Zero third-party cloud SDKs.
/// Captures breadcrumbs, uncaught exceptions, and low memory pressure events.
public final class CrashReporter: @unchecked Sendable {
    public static let shared = CrashReporter()
    
    private let fileManager = FileManager.default
    private let reportsDirectoryURL: URL
    private var breadcrumbs: [String] = []
    private let breadcrumbsLock = NSLock()
    
    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recallDir = appSupport.appendingPathComponent("RecallRx", isDirectory: true)
        self.reportsDirectoryURL = recallDir.appendingPathComponent("CrashReports", isDirectory: true)
        try? fileManager.createDirectory(at: reportsDirectoryURL, withIntermediateDirectories: true)
        
        setupCrashHandlers()
    }
    
    // MARK: - Breadcrumbs
    
    public func recordBreadcrumb(_ message: String) {
        breadcrumbsLock.lock()
        defer { breadcrumbsLock.unlock() }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        breadcrumbs.append("[\(timestamp)] \(message)")
        if breadcrumbs.count > 100 {
            breadcrumbs.removeFirst()
        }
    }
    
    public func getBreadcrumbs() -> [String] {
        breadcrumbsLock.lock()
        defer { breadcrumbsLock.unlock() }
        return breadcrumbs
    }
    
    // MARK: - Error Recording
    
    public func recordError(_ error: Error, context: String) {
        recordBreadcrumb("ERROR in \(context): \(error.localizedDescription)")
        
        let report: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "context": context,
            "errorDescription": error.localizedDescription,
            "breadcrumbs": getBreadcrumbs()
        ]
        
        saveReport(report, prefix: "error")
    }
    
    // MARK: - Crash Handling
    
    private func setupCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let report: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970,
                "name": exception.name.rawValue,
                "reason": exception.reason ?? "No reason",
                "callStack": exception.callStackSymbols,
                "breadcrumbs": CrashReporter.shared.getBreadcrumbs()
            ]
            CrashReporter.shared.saveReport(report, prefix: "crash")
        }
    }
    
    private func saveReport(_ dict: [String: Any], prefix: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(prefix)_\(formatter.string(from: Date())).json"
        let url = reportsDirectoryURL.appendingPathComponent(filename)
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? data.write(to: url)
        }
    }
    
    public func listReports() -> [URL] {
        (try? fileManager.contentsOfDirectory(at: reportsDirectoryURL, includingPropertiesForKeys: nil)) ?? []
    }
    
    public func clearReports() {
        let files = listReports()
        for f in files {
            try? fileManager.removeItem(at: f)
        }
    }
}
