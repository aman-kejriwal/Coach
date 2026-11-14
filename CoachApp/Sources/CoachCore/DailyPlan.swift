import Foundation

/// What to revise today: due files first, by priority, topped up with files that are nearly due so
/// there's always something to do, and capped at the daily goal so a backlog stays manageable.
public struct DailyPlan: Sendable {
    /// Due files to do today, highest priority first (at most the goal's remaining slots).
    public var due: [Topic] = []
    /// "Getting ahead": not due yet, but closest to it. Only added when fewer files are due than the goal.
    public var ahead: [Topic] = []
    /// Due files beyond today's goal. Still due; you can keep going.
    public var moreDue: [Topic] = []
    /// Files revised today (they count toward the goal).
    public var doneToday: Int = 0
    public var goal: Int = 0

    /// Today's list, in order.
    public var today: [Topic] { due + ahead }
    /// Today's list followed by any extra due files: everything worth doing today, in order.
    public var all: [Topic] { due + ahead + moreDue }
    public var isGoalMet: Bool { goal > 0 && doneToday >= goal }

    /// Priority of a file: how far through its gap it is (1 = due today, 1.5 = overdue by half its gap),
    /// nudged up for low confidence so critical files win ties.
    public static func priority(_ t: Topic, now: Date = Date()) -> Double {
        t.gapProgress(now: now) + Double(5 - t.confidence) * 0.08
    }

    /// Highest priority first.
    public static func byPriority(now: Date) -> (Topic, Topic) -> Bool {
        { a, b in
            let pa = priority(a, now: now), pb = priority(b, now: now)
            if abs(pa - pb) > 0.0001 { return pa > pb }
            return Topic.urgency(a, b)
        }
    }

    public init() {}

    /// `goal` is files per day (0 = no goal: all due files, no extras).
    public init(topics: [Topic], goal: Int, now: Date = Date(), calendar: Calendar = .current) {
        self.goal = max(0, goal)
        let sort = Self.byPriority(now: now)
        let reviewedToday: (Topic) -> Bool = { t in t.lastReviewed.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        doneToday = topics.filter(reviewedToday).count

        let dueFiles = topics.filter { $0.isDue(now: now) }.sorted(by: sort)
        guard self.goal > 0 else { due = dueFiles; return }

        let slots = max(0, self.goal - doneToday)
        due = Array(dueFiles.prefix(slots))
        moreDue = Array(dueFiles.dropFirst(slots))
        let free = slots - due.count
        if free > 0 {
            ahead = Array(topics.filter { !$0.isDue(now: now) && !reviewedToday($0) }.sorted(by: sort).prefix(free))
        }
    }
}

extension Topic {
    /// Days from the last review (or when it was added) to the next one.
    public func gapDays(calendar: Calendar = .current) -> Int {
        if let start = lastReviewed ?? created,
           let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: nextReview)).day, d > 0 {
            return d
        }
        return Scheduler.intervalDays(confidence: confidence, streak: streak)
    }

    /// How far through its gap the file is: 0 = just revised, 1 = due today, above 1 = overdue.
    public func gapProgress(now: Date = Date(), calendar: Calendar = .current) -> Double {
        let gap = Double(gapDays(calendar: calendar))
        return (gap - Double(daysUntilDue(now: now, calendar: calendar))) / gap
    }
}
