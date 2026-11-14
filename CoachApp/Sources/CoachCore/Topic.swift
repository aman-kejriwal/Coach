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
    /// Folder path inside the Coach folder, e.g. ["DSA", "Graphs", "Shortest Paths"]. The folders are the hierarchy.
    public var folder: [String]
    public var confidence: Int
    public var created: Date?
    public var lastReviewed: Date?
    public var nextReview: Date
    public var reviewCount: Int
    public var streak: Int

    /// The note's file name is the topic title, so renaming in Obsidian renames the topic.
    public var title: String { url.deletingPathExtension().lastPathComponent }
    /// Top-level folder (the subject).
    public var subjectName: String { folder.first ?? "Coach" }
    /// "DSA › Graphs › Shortest Paths"
    public var folderDisplay: String { folder.isEmpty ? "Coach" : folder.joined(separator: " › ") }
    /// True when this file is inside `path` (at any depth). The empty path is the whole Coach folder.
    public func isInside(_ path: [String]) -> Bool { folder.starts(with: path) }

    /// `coachRoot` is the Coach folder; the file's folder path is computed relative to it.
    public init?(document doc: NoteDocument, url: URL, coachRoot: URL? = nil, now: Date = Date()) {
        guard let id = doc.value(for: CoachKey.id) else { return nil }
        self.id = id
        self.url = url
        folder = coachRoot.map { Self.relativeFolder(of: url, in: $0) } ?? []
        confidence = Confidence.clamp(Int(doc.value(for: CoachKey.confidence) ?? "") ?? 3)
        created = CoachDates.parse(doc.value(for: CoachKey.created))
        lastReviewed = CoachDates.parse(doc.value(for: CoachKey.lastReviewed))
        nextReview = CoachDates.parse(doc.value(for: CoachKey.nextReview)) ?? Calendar.current.startOfDay(for: now)
        reviewCount = Int(doc.value(for: CoachKey.reviewCount) ?? "") ?? 0
        streak = Int(doc.value(for: CoachKey.streak) ?? "") ?? 0
    }

    /// Folder components of `url` relative to `root` (empty if the file sits directly in root or outside it).
    public static func relativeFolder(of url: URL, in root: URL) -> [String] {
        let rootParts = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let dirParts = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard dirParts.starts(with: rootParts) else { return [] }
        return Array(dirParts.dropFirst(rootParts.count))
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
