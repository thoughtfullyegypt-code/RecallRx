import Foundation

/// Validated SM-2 options shared by the scheduler and interval previews.
struct SM2SchedulingParameters: Sendable, Equatable {
    let learningStepsMinutes: [Double]
    let graduatingInterval: Double
    let easyInterval: Double

    private static let defaultLearningSteps: [Double] = [1, 10]
    private static let maximumInterval = 36500.0

    init(
        learningStepsMinutes: [Double] = [1, 10],
        graduatingInterval: Double = 1,
        easyInterval: Double = 4
    ) {
        self.learningStepsMinutes = Self.validatedSteps(learningStepsMinutes)
        self.graduatingInterval = Self.validatedInterval(graduatingInterval, fallback: 1)
        self.easyInterval = Self.validatedInterval(easyInterval, fallback: 4)
    }

    static func load(from defaults: UserDefaults = .standard) -> SM2SchedulingParameters {
        let steps = defaults.string(forKey: "learningSteps")
            .flatMap(parseLearningSteps) ?? defaultLearningSteps
        let graduating = (defaults.object(forKey: "graduatingInterval") as? NSNumber)?.doubleValue ?? 1
        let easy = (defaults.object(forKey: "easyInterval") as? NSNumber)?.doubleValue ?? 4
        return SM2SchedulingParameters(
            learningStepsMinutes: steps,
            graduatingInterval: graduating,
            easyInterval: easy
        )
    }

    /// Space-separated tokens accept seconds, minutes, hours, or days; bare numbers are minutes.
    /// Reject the whole malformed sequence so a typo cannot silently remove a learning step.
    static func parseLearningSteps(_ text: String) -> [Double]? {
        let tokens = text.lowercased().split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return nil }
        let suffixes: [(String, Double)] = [
            ("minutes", 1), ("minute", 1), ("seconds", 1.0 / 60), ("second", 1.0 / 60),
            ("hours", 60), ("hour", 60), ("days", 1440), ("day", 1440),
            ("mins", 1), ("min", 1), ("secs", 1.0 / 60), ("sec", 1.0 / 60),
            ("hrs", 60), ("hr", 60), ("s", 1.0 / 60), ("m", 1), ("h", 60), ("d", 1440)
        ]
        var parsed: [Double] = []
        for token in tokens {
            let suffix = suffixes.first { token.hasSuffix($0.0) }
            let number = suffix.map { token.dropLast($0.0.count) } ?? token
            guard let value = Double(number) else { return nil }
            let minutes = value * (suffix?.1 ?? 1)
            guard minutes.isFinite, minutes > 0, minutes <= maximumInterval * 1440 else { return nil }
            parsed.append(minutes)
        }
        return parsed
    }

    private static func validatedSteps(_ values: [Double]) -> [Double] {
        guard !values.isEmpty,
              values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= maximumInterval * 1440 }) else {
            return defaultLearningSteps
        }
        return values
    }

    private static func validatedInterval(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite, value >= 1 else { return fallback }
        return min(value, maximumInterval)
    }
}
