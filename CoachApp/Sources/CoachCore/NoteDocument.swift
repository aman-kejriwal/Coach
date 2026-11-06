import Foundation

/// A Markdown note split into YAML frontmatter lines and a body.
///
/// Edits are line-based on purpose: only the keys Coach owns are touched, and every
/// other line of the user's frontmatter (comments, lists, formatting) is kept as-is.
public struct NoteDocument: Equatable, Sendable {
    /// Raw lines between the opening and closing `---`, or nil when the note has no frontmatter.
    public private(set) var frontmatter: [String]?
    public var body: String
    private let usesCRLF: Bool

    public init(text: String) {
        usesCRLF = text.contains("\r\n")
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let lines = normalized.components(separatedBy: "\n")

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.indices.dropFirst().first(where: {
               let t = lines[$0].trimmingCharacters(in: .whitespaces)
               return t == "---" || t == "..."
           }) {
            frontmatter = Array(lines[1..<end])
            body = lines[(end + 1)...].joined(separator: "\n")
        } else {
            frontmatter = nil
            body = normalized
        }
    }

    public var hasFrontmatter: Bool { frontmatter != nil }

    // MARK: Frontmatter

    public func value(for key: String) -> String? {
        guard let fm = frontmatter, let i = keyIndex(key, in: fm) else { return nil }
        var raw = String(fm[i].dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }
        if !(raw.hasPrefix("\"") || raw.hasPrefix("'")), let hash = raw.range(of: " #") {
            raw = String(raw[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        let value = YAMLScalar.unquote(raw)
        return value.isEmpty ? nil : value
    }

    /// Sets (or removes, when `value` is nil) a top-level scalar key.
    public mutating func set(_ key: String, _ value: String?, quoted: Bool = false) {
        if frontmatter == nil {
            guard value != nil else { return }
            frontmatter = []
        }
        var fm = frontmatter!
        let line = value.map { "\(key): \(quoted ? YAMLScalar.quote($0) : $0)" }

        if let i = keyIndex(key, in: fm) {
            var end = i + 1
            while end < fm.count, Self.isContinuation(fm[end]) { end += 1 }
            fm.removeSubrange((i + 1)..<end)
            if let line { fm[i] = line } else { fm.remove(at: i) }
        } else if let line {
            fm.append(line)
        }
        frontmatter = fm
    }

    /// Adds a block list key (e.g. `tags`) only if the key does not already exist.
    public mutating func addListIfMissing(_ key: String, items: [String]) {
        if frontmatter == nil { frontmatter = [] }
        guard keyIndex(key, in: frontmatter!) == nil else { return }
        frontmatter!.append("\(key):")
        frontmatter!.append(contentsOf: items.map { "  - \($0)" })
    }

    private func keyIndex(_ key: String, in fm: [String]) -> Int? {
        fm.firstIndex { $0.hasPrefix(key + ":") }
    }

    private static func isContinuation(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("- ") || line == "-"
    }

    // MARK: Body sections

    /// Text under a heading (e.g. `## Recall question`) up to the next heading of the same or higher level.
    public func section(_ heading: String) -> String? {
        let lines = body.components(separatedBy: "\n")
        guard let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else { return nil }
        let level = Self.headingLevel(heading) ?? 6
        let end = lines[(h + 1)...].firstIndex(where: { (Self.headingLevel($0) ?? 99) <= level }) ?? lines.count
        let text = lines[(h + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Appends a line at the end of a section, creating the section at the bottom of the note if needed.
    public mutating func appendLine(_ line: String, toSection heading: String) {
        var lines = body.components(separatedBy: "\n")
        if let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) {
            let level = Self.headingLevel(heading) ?? 6
            let end = lines[(h + 1)...].firstIndex(where: { (Self.headingLevel($0) ?? 99) <= level }) ?? lines.count
            var insertAt = end
            while insertAt > h + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
            lines.insert(line, at: insertAt)
        } else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines.append(heading)
            lines.append(line)
            lines.append("")
        }
        body = lines.joined(separator: "\n")
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.first == " " ? hashes : nil
    }

    // MARK: Output

    public func render() -> String {
        var out: String
        if let fm = frontmatter {
            out = fm.isEmpty ? "---\n---\n" : "---\n" + fm.joined(separator: "\n") + "\n---\n"
            out += body
        } else {
            out = body
        }
        return usesCRLF ? out.replacingOccurrences(of: "\n", with: "\r\n") : out
    }
}

public enum YAMLScalar {
    public static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static func unquote(_ raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return raw
    }
}
