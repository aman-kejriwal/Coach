import Foundation

/// Frontmatter keys owned by Coach. All are prefixed so they never collide with the user's own properties.
public enum CoachKey {
    public static let id = "coach_id"
    public static let subject = "coach_subject"
    public static let confidence = "coach_confidence"
    public static let created = "coach_created"
    public static let lastReviewed = "coach_last_reviewed"
    public static let nextReview = "coach_next_review"
    public static let reviewCount = "coach_review_count"
    public static let streak = "coach_streak"
    public static let schema = "coach_schema"

    public static let all = [id, subject, confidence, created, lastReviewed, nextReview, reviewCount, streak, schema]
    public static let currentSchema = 1

    public static let reviewLogHeading = "## Review log"
    public static let recallHeading = "## Recall question"
    public static let recallAttemptsHeading = "## Recall attempts"
}

public struct Topic: Identifiable, Hashable, Sendable {
    public var id: String
    public var url: URL
    public var subject: String?
    public var confidence: Int
    public var created: Date?
    public var lastReviewed: Date?
    public var nextReview: Date
    public var reviewCount: Int
    public var streak: Int

    /// The note's file name is the topic title, so renaming in Obsidian renames the topic.
    public var title: String { url.deletingPathExtension().lastPathComponent }
    public var subjectName: String { subject?.isEmpty == false ? subject! : "General" }

    public init?(document doc: NoteDocument, url: URL, now: Date = Date()) {
        guard let id = doc.value(for: CoachKey.id) else { return nil }
        self.id = id
        self.url = url
        subject = doc.value(for: CoachKey.subject)
        confidence = Confidence.clamp(Int(doc.value(for: CoachKey.confidence) ?? "") ?? 3)
        created = CoachDates.parse(doc.value(for: CoachKey.created))
        lastReviewed = CoachDates.parse(doc.value(for: CoachKey.lastReviewed))
        nextReview = CoachDates.parse(doc.value(for: CoachKey.nextReview)) ?? Calendar.current.startOfDay(for: now)
        reviewCount = Int(doc.value(for: CoachKey.reviewCount) ?? "") ?? 0
        streak = Int(doc.value(for: CoachKey.streak) ?? "") ?? 0
    }

    /// Negative = overdue by that many days, 0 = due today, positive = days remaining.
    public func daysUntilDue(now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: nextReview)
        ).day ?? 0
    }

    public func isDue(now: Date = Date()) -> Bool { daysUntilDue(now: now) <= 0 }

    public func dueDescription(now: Date = Date()) -> String {
        switch daysUntilDue(now: now) {
        case ..<(-1): return "Overdue \(-daysUntilDue(now: now)) days"
        case -1: return "Overdue 1 day"
        case 0: return "Due today"
        case 1: return "Tomorrow"
        case let d: return "In \(d) days"
        }
    }

    /// Most urgent first: earliest due date, then lowest confidence (most important), then title.
    public static func urgency(_ a: Topic, _ b: Topic) -> Bool {
        if a.nextReview != b.nextReview { return a.nextReview < b.nextReview }
        if a.confidence != b.confidence { return a.confidence < b.confidence }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
