import Foundation

/// One line of a note's `## Review log`, e.g. `- 2026-11-05 14:32 · reviewed · confidence 3 · 4 min · next 2026-11-09`.
public struct ReviewLogEntry: Hashable, Sendable {
    public let date: Date
    public let text: String
    /// Confidence recorded by this entry (the new value for "confidence 3 → 2"), if any.
    public let confidence: Int?
    public var isReview: Bool { text.hasPrefix("reviewed") }
}

public enum ReviewLog {
    public static func entries(in doc: NoteDocument) -> [ReviewLogEntry] {
        guard let section = doc.section(CoachKey.reviewLogHeading) else { return [] }
        return section.components(separatedBy: "\n").compactMap(parse)
    }

    static func parse(_ line: String) -> ReviewLogEntry? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("- ") else { return nil }
        let rest = t.dropFirst(2)
        guard rest.count > 16, let date = CoachDates.parse(String(rest.prefix(16))) else { return nil }
        var text = String(rest.dropFirst(16)).trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("·") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return ReviewLogEntry(date: date, text: text, confidence: confidence(in: text))
    }

    private static func confidence(in text: String) -> Int? {
        guard let r = text.range(of: "confidence ") else { return nil }
        var tail = text[r.upperBound...]
        if let arrow = tail.range(of: "→") { tail = tail[arrow.upperBound...] }
        let digits = tail.drop(while: { $0 == " " }).prefix(while: \.isNumber)
        return Int(digits).map(Confidence.clamp)
    }
}

extension NoteDocument {
    /// The body without the given sections (and without a leading `# Title` heading matching `title`).
    public func body(removingSections headings: [String], title: String? = nil) -> String {
        var lines = body.components(separatedBy: "\n")
        for heading in headings {
            guard let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else { continue }
            let level = Self.headingLevel(heading) ?? 6
            let end = lines[(h + 1)...].firstIndex(where: { (Self.headingLevel($0) ?? 99) <= level }) ?? lines.count
            lines.removeSubrange(h..<end)
        }
        if let title, let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces) == "# \(title)" {
            lines.remove(at: first)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
