import Foundation

/// Confidence 1–5. Low confidence doubles as "important / can't afford to forget":
/// those topics come back sooner and are never allowed to drift far away.
public enum Confidence {
    public static let range = 1...5

    public static func clamp(_ c: Int) -> Int { min(max(c, range.lowerBound), range.upperBound) }

    public static func label(_ c: Int) -> String {
        ["Critical", "Weak", "Okay", "Good", "Solid"][clamp(c) - 1]
    }

    public static func detail(_ c: Int) -> String {
        [
            "Barely remember it, or can't afford to forget it. Reviewed very often.",
            "Shaky. Comes back within a few days.",
            "Mostly there. Normal spacing.",
            "Comfortable. Longer gaps.",
            "Know it cold. Occasional check-ins.",
        ][clamp(c) - 1]
    }
}

/// Spaced-repetition scheduling.
///
/// interval = base(confidence) × 1.6^streak, capped per confidence level.
/// The streak counts consecutive reviews rated 3+; a 1 or 2 resets it.
///
/// | conf | base | cap  |
/// |------|------|------|
/// | 1    | 1d   | 5d   |
/// | 2    | 2d   | 12d  |
/// | 3    | 4d   | 45d  |
/// | 4    | 7d   | 90d  |
/// | 5    | 14d  | 180d |
public enum Scheduler {
    public static let growth = 1.6
    private static let base: [Double] = [1, 2, 4, 7, 14]
    private static let cap: [Double] = [5, 12, 45, 90, 180]

    public static func intervalDays(confidence: Int, streak: Int) -> Int {
        let i = Confidence.clamp(confidence) - 1
        let raw = base[i] * pow(growth, Double(min(max(streak, 0), 10)))
        return max(1, Int(min(raw, cap[i]).rounded()))
    }

    public struct Result: Equatable, Sendable {
        public let nextReview: Date
        public let streak: Int
    }

    /// Schedule after a review rated `confidence`.
    ///
    /// `progress` is how far through its gap the file was (see `Topic.gapProgress`); 1 or more = on time.
    /// Revising early proves less (it was still fresh), so a good rating grows the gap less:
    /// the gap is scaled by 0.5…1 and the streak only grows from 75% of the way through.
    /// A weak rating counts in full whenever it happens.
    public static func afterReview(
        confidence: Int, previousStreak: Int, reviewedAt: Date, progress: Double = 1, calendar: Calendar = .current
    ) -> Result {
        let weak = Confidence.clamp(confidence) <= 2
        let p = min(max(progress, 0), 1)
        if !weak && p < 1 {
            let full = Double(intervalDays(confidence: confidence, streak: previousStreak))
            let days = max(1, Int((full * (0.5 + 0.5 * p)).rounded()))
            let next = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: reviewedAt))!
            return Result(nextReview: next, streak: p >= 0.75 ? previousStreak + 1 : previousStreak)
        }
        let days = intervalDays(confidence: confidence, streak: weak ? 0 : previousStreak)
        let next = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: reviewedAt))!
        return Result(nextReview: next, streak: weak ? 0 : previousStreak + 1)
    }

    /// First review for a topic that was just added and never revised: half the normal gap, at least 1 day.
    public static func firstReview(confidence: Int, addedAt: Date, calendar: Calendar = .current) -> Date {
        let days = max(1, Int((Double(intervalDays(confidence: confidence, streak: 0)) / 2).rounded()))
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: addedAt))!
    }
}

extension Scheduler {
    /// Schedule after revising `topic` now, taking into account how early it is.
    public static func afterReview(of topic: Topic, confidence: Int, at date: Date = Date(),
                                   calendar: Calendar = .current) -> Result {
        afterReview(confidence: confidence, previousStreak: topic.streak, reviewedAt: date,
                    progress: topic.gapProgress(now: date, calendar: calendar), calendar: calendar)
    }
}
