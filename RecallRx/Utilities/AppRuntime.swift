import Foundation

/// Process policy kept separate from persisted user preferences.
enum AppRuntime {
    static var isTesting: Bool {
        isTesting(environment: ProcessInfo.processInfo.environment)
    }

    static func isTesting(environment: [String: String]) -> Bool {
        environment["RECALLRX_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    static var isUIAutomationEnabled: Bool {
        isUIAutomationEnabled(arguments: ProcessInfo.processInfo.arguments,
                              environment: ProcessInfo.processInfo.environment)
    }

    static func isUIAutomationEnabled(arguments: [String], environment: [String: String]) -> Bool {
        #if DEBUG
        return !isTesting(environment: environment) && arguments.contains("--enable-ui-automation")
        #else
        return false
        #endif
    }

    /// Shared service defaults must never touch the user's app group during hosted tests.
    static func defaults(suiteName: String? = nil) -> UserDefaults {
        if isTesting {
            return UserDefaults(suiteName: "RecallRx.Tests.\(UUID().uuidString)") ?? UserDefaults()
        }
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        return .standard
    }
}
