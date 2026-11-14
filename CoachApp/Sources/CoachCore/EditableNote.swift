import Foundation

/// The parts of a note the user writes: the recall question and the note itself.
/// Everything else (frontmatter, review log, recall attempts) belongs to Coach and is kept as-is when saving.
public struct EditableNote: Equatable, Sendable {
    public var recallQuestion: String
    public var content: String

    public init(recallQuestion: String = "", content: String = "") {
        self.recallQuestion = recallQuestion
        self.content = content
    }

    /// Compares ignoring leading/trailing whitespace, so a stray newline doesn't count as a change.
    public func isSame(as other: EditableNote) -> Bool {
        Self.trim(recallQuestion) == Self.trim(other.recallQuestion) && Self.trim(content) == Self.trim(other.content)
    }

    public static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension NoteDocument {
    /// Sections Coach writes. They are not shown in the editor and are always kept.
    static let coachOwnedSections = [CoachKey.recallAttemptsHeading, CoachKey.reviewLogHeading]

    public var editable: EditableNote {
        EditableNote(
            recallQuestion: section(CoachKey.recallHeading) ?? "",
            content: body(removingSections: [CoachKey.recallHeading] + Self.coachOwnedSections)
        )
    }

    /// Replaces the recall question and note text. Frontmatter, recall attempts and the review log are kept.
    /// The recall question goes right under the `# Title` heading (or at the top), Coach's sections at the end.
    public mutating func applyEditable(_ edit: EditableNote) {
        // Coach's sections, in the order they already appear in the file.
        let lines = body.components(separatedBy: "\n")
        let kept = Self.coachOwnedSections
            .compactMap { h in lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == h }.map { (h, $0) } }
            .sorted { $0.1 < $1.1 }
            .compactMap { rawSection($0.0) }

        var contentLines = EditableNote.trim(edit.content).components(separatedBy: "\n")
        if contentLines == [""] { contentLines = [] }

        var recallBlock: [String] = []
        let q = EditableNote.trim(edit.recallQuestion)
        if !q.isEmpty { recallBlock = [CoachKey.recallHeading] + q.components(separatedBy: "\n") }

        var blocks: [[String]] = []
        if let first = contentLines.first, Self.headingLevel(first) == 1 {
            blocks.append([first])
            if !recallBlock.isEmpty { blocks.append(recallBlock) }
            let rest = Array(contentLines.dropFirst()).dropLeadingBlankLines()
            if !rest.isEmpty { blocks.append(rest) }
        } else {
            if !recallBlock.isEmpty { blocks.append(recallBlock) }
            if !contentLines.isEmpty { blocks.append(contentLines) }
        }
        blocks.append(contentsOf: kept)

        body = blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    /// A section's heading and lines, trailing blank lines removed.
    private func rawSection(_ heading: String) -> [String]? {
        let lines = body.components(separatedBy: "\n")
        guard let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else { return nil }
        let level = Self.headingLevel(heading) ?? 6
        let end = lines[(h + 1)...].firstIndex(where: { (Self.headingLevel($0) ?? 99) <= level }) ?? lines.count
        var section = Array(lines[h..<end])
        while let last = section.last, last.trimmingCharacters(in: .whitespaces).isEmpty { section.removeLast() }
        return section
    }
}

private extension Array where Element == String {
    func dropLeadingBlankLines() -> [String] {
        Array(drop { $0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
