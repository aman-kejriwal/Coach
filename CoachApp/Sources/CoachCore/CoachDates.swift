import Foundation

/// Date formats written to the vault. Everything is local time with an explicit offset,
/// so "due today" never shifts at midnight or when travelling.
public enum CoachDates {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let dayFormatter = formatter("yyyy-MM-dd")
    private static let logFormatter = formatter("yyyy-MM-dd HH:mm")
    private static let fallbackFormats = [
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
    ].map(formatter)

    /// `2026-11-05T14:32:00+05:30`
    public static func dateTime(_ date: Date) -> String { iso.string(from: date) }

    /// `2026-11-07`
    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// `2026-11-05 14:32` (used in the review log)
    public static func logStamp(_ date: Date) -> String { logFormatter.string(from: date) }

    public static func parse(_ string: String?) -> Date? {
        guard let s = string?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let d = iso.date(from: s) { return d }
        for f in fallbackFormats { if let d = f.date(from: s) { return d } }
        return nil
    }
}
