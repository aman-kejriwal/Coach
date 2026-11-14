import Foundation

/// One change to apply to the editor's text: replace `range` (in the old text) with `replacement`,
/// then select `selection` (in the new text). Ranges are UTF-16, like NSTextView.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// Editing commands for the Markdown editor (formatting, lists, headings). Pure functions on text,
/// so the editor can apply them with undo support and they can be tested without AppKit.
public enum MarkdownEditing {
    public enum LineStyle: Sendable { case bullet, numbered, task, quote }

    // MARK: Lines

    struct ParsedLine {
        enum Kind { case bullet, numbered, task, quote }
        var indent: String
        var kind: Kind?
        var marker: String   // e.g. "- ", "3. ", "- [ ] ", "> "
        var checked = false
        var number = 0
        var numberSuffix = "."
        var bulletChar = "-"
        var rest: String     // text after the marker
    }

    private static let linePattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+]) \[([ xX])\] |([-*+]) |(\d{1,9})([.)]) |(> ?))?"#)

    static func parse(_ line: String) -> ParsedLine {
        let ns = line as NSString
        let m = linePattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))!
        func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        var p = ParsedLine(indent: g(1) ?? "", kind: nil, marker: "", rest: ns.substring(from: m.range.length))
        let markerRange = NSRange(location: m.range(at: 1).length, length: m.range.length - m.range(at: 1).length)
        p.marker = ns.substring(with: markerRange)
        if let b = g(2) { p.kind = .task; p.bulletChar = b; p.checked = g(3)?.lowercased() == "x" }
        else if let b = g(4) { p.kind = .bullet; p.bulletChar = b }
        else if let n = g(5) { p.kind = .numbered; p.number = Int(n) ?? 1; p.numberSuffix = g(6) ?? "." }
        else if g(7) != nil { p.kind = .quote }
        return p
    }

    /// Range of the lines touched by `selection`, without the final line break.
    static func linesRange(_ ns: NSString, _ selection: NSRange) -> NSRange {
        var r = ns.lineRange(for: selection)
        // A selection ending right after a line break doesn't include the next line.
        if selection.length > 0, NSMaxRange(selection) == r.location + r.length, NSMaxRange(selection) > selection.location,
           ns.character(at: NSMaxRange(selection) - 1) == 10, r.length > 0 {
            r = ns.lineRange(for: NSRange(location: selection.location, length: selection.length - 1))
        }
        if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
        return r
    }

    /// Rewrites every line in the selection. Keeps a caret on the same text, or selects the whole new block.
    static func transformLines(_ text: String, _ selection: NSRange, _ change: ([String]) -> [String]) -> TextEdit {
        let ns = text as NSString
        let r = linesRange(ns, selection)
        let old = ns.substring(with: r).components(separatedBy: "\n")
        let new = change(old)
        let replacement = new.joined(separator: "\n")
        let newLength = (replacement as NSString).length
        let sel: NSRange
        if selection.length == 0 && old.count == 1 {
            let delta = (new[0] as NSString).length - (old[0] as NSString).length
            let loc = min(max(r.location, selection.location + delta), r.location + newLength)
            sel = NSRange(location: loc, length: 0)
        } else {
            sel = NSRange(location: r.location, length: newLength)
        }
        return TextEdit(range: r, replacement: replacement, selection: sel)
    }

    // MARK: Return / Tab

    /// What Return should do with the caret at `caret`: continue a list, end an empty list item,
    /// or keep the indentation. nil means "insert a plain newline".
    public static func newline(in text: String, at caret: Int) -> TextEdit? {
        if let code = codeNewline(in: text, at: caret) { return code }
        let ns = text as NSString
        let lr = linesRange(ns, NSRange(location: caret, length: 0))
        let line = ns.substring(with: lr)
        let p = parse(line)
        let caretInLine = caret - lr.location
        let prefixLength = ((p.indent + p.marker) as NSString).length

        guard let kind = p.kind else {
            guard !p.indent.isEmpty, caretInLine >= (p.indent as NSString).length else { return nil }
            return insert("\n" + p.indent, at: caret)
        }
        guard caretInLine >= prefixLength else { return nil }

        if p.rest.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: outdent it, or end the list when it's already at the left edge.
            if !p.indent.isEmpty {
                let indent = outdented(p.indent)
                let newLine = indent + p.marker + p.rest
                return TextEdit(range: lr, replacement: newLine,
                                selection: NSRange(location: lr.location + (newLine as NSString).length, length: 0))
            }
            return TextEdit(range: lr, replacement: "", selection: NSRange(location: lr.location, length: 0))
        }

        let next: String
        switch kind {
        case .task: next = "\(p.bulletChar) [ ] "
        case .bullet: next = "\(p.bulletChar) "
        case .numbered: next = "\(p.number + 1)\(p.numberSuffix) "
        case .quote: next = "> "
        }
        return insert("\n" + p.indent + next, at: caret)
    }

    /// Tab / Shift-Tab on list items: indent or outdent every selected line. nil means "not a list".
    public static func indent(in text: String, selection: NSRange, outdent: Bool) -> TextEdit? {
        if isInCodeBlock(text, at: selection.location) { return codeIndent(in: text, selection: selection, outdent: outdent) }
        let ns = text as NSString
        let lines = ns.substring(with: linesRange(ns, selection)).components(separatedBy: "\n")
        guard lines.contains(where: { parse($0).kind != nil && parse($0).kind != .quote }) else { return nil }
        return transformLines(text, selection) { lines in
            lines.map { line in
                if outdent { return outdented(prefix: line) }
                return line.trimmingCharacters(in: .whitespaces).isEmpty ? line : "\t" + line
            }
        }
    }

    private static func outdented(_ indent: String) -> String {
        if indent.hasPrefix("\t") { return String(indent.dropFirst()) }
        let spaces = indent.prefix(while: { $0 == " " }).count
        return String(indent.dropFirst(min(4, spaces)))
    }

    private static func outdented(prefix line: String) -> String {
        let indentCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = String(line.prefix(indentCount))
        return outdented(indent) + line.dropFirst(indentCount)
    }

    // MARK: Inline formatting

    /// Bold (`**`), italic (`*`), strikethrough (`~~`), highlight (`==`), inline code (`` ` ``).
    /// Wraps the selection, or unwraps it when it's already wrapped. With no selection, inserts a pair.
    public static func toggleWrap(_ marker: String, in text: String, selection sel: NSRange) -> TextEdit {
        let ns = text as NSString
        let m = (marker as NSString).length
        let unit = (marker as NSString).character(at: 0)

        func run(from start: Int, step: Int) -> Int {
            var i = start, n = 0
            while i >= 0, i < ns.length, ns.character(at: i) == unit { n += 1; i += step }
            return n
        }
        func wrapped(before: Int, after: Int) -> Bool {
            guard before >= m, after >= m else { return false }
            // "*" next to "**" is bold, not italic: italic needs an odd run (1 or 3).
            return marker == "*" ? before % 2 == 1 && after % 2 == 1 : true
        }

        let before = run(from: sel.location - 1, step: -1)
        let after = run(from: NSMaxRange(sel), step: 1)
        if wrapped(before: before, after: after) {
            let selected = ns.substring(with: sel)
            return TextEdit(range: NSRange(location: sel.location - m, length: sel.length + 2 * m),
                            replacement: selected, selection: NSRange(location: sel.location - m, length: sel.length))
        }

        if sel.length >= 2 * m {
            let selected = ns.substring(with: sel)
            let inner = NSRange(location: sel.location + m, length: sel.length - 2 * m)
            if selected.hasPrefix(marker), selected.hasSuffix(marker),
               wrapped(before: run(from: sel.location, step: 1), after: run(from: NSMaxRange(sel) - 1, step: -1)) {
                let innerText = ns.substring(with: inner)
                return TextEdit(range: sel, replacement: innerText,
                                selection: NSRange(location: sel.location, length: inner.length))
            }
        }

        // Don't wrap the spaces around a double-clicked word.
        var target = sel
        while target.length > 0, ns.character(at: NSMaxRange(target) - 1) == 32 { target.length -= 1 }
        let selected = ns.substring(with: target)
        return TextEdit(range: target, replacement: marker + selected + marker,
                        selection: NSRange(location: target.location + m, length: target.length))
    }

    // MARK: Line formatting

    /// Turns the selected lines into a heading of `level` (1–6), or back into text when they already are,
    /// or when `level` is 0.
    public static func setHeading(_ level: Int, in text: String, selection: NSRange) -> TextEdit {
        transformLines(text, selection) { lines in
            let stripped = lines.map { stripHeading($0) }
            let allAlready = level > 0 && zip(lines, stripped).allSatisfy { line, s in
                s.level == level || line.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return stripped.map { s in
                guard level > 0, !allAlready, !s.text.isEmpty || lines.count == 1 else { return s.text }
                return String(repeating: "#", count: level) + " " + s.text
            }
        }
    }

    static func stripHeading(_ line: String) -> (level: Int, text: String) {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return (0, line) }
        return (hashes, String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces))
    }

    /// Bullet / numbered / checklist / quote for the selected lines. Applying the same style again removes it;
    /// on a checklist it ticks (or unticks) the items instead.
    public static func toggleLineStyle(_ style: LineStyle, in text: String, selection: NSRange) -> TextEdit {
        transformLines(text, selection) { lines in
            let parsed = lines.map(parse)
            let content = parsed.enumerated().filter { !lines[$0.offset].trimmingCharacters(in: .whitespaces).isEmpty || lines.count == 1 }
            let target: ParsedLine.Kind = switch style {
            case .bullet: .bullet
            case .numbered: .numbered
            case .task: .task
            case .quote: .quote
            }
            let allHave = !content.isEmpty && content.allSatisfy { $0.element.kind == target }

            if allHave && style == .task {
                let tick = !content.allSatisfy(\.element.checked)
                return parsed.map { p in
                    guard p.kind == .task else { return p.indent + p.marker + p.rest }
                    return p.indent + "\(p.bulletChar) [\(tick ? "x" : " ")] " + p.rest
                }
            }

            var number = 0
            return parsed.enumerated().map { i, p in
                let isBlank = lines[i].trimmingCharacters(in: .whitespaces).isEmpty && lines.count > 1
                if isBlank { return lines[i] }
                if allHave { return p.indent + p.rest }
                number += 1
                let marker = switch style {
                case .bullet: "- "
                case .numbered: "\(number). "
                case .task: "- [ ] "
                case .quote: "> "
                }
                return p.indent + marker + p.rest
            }
        }
    }

    // MARK: Inserting

    public static func insert(_ s: String, at location: Int, caretOffset: Int? = nil) -> TextEdit {
        let len = (s as NSString).length
        return TextEdit(range: NSRange(location: location, length: 0), replacement: s,
                        selection: NSRange(location: location + (caretOffset ?? len), length: 0))
    }

    /// `[text](url)`, with the caret where you still need to type.
    public static func link(in text: String, selection: NSRange) -> TextEdit {
        let selected = (text as NSString).substring(with: selection)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return TextEdit(range: selection, replacement: "[](\(selected))",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        let len = (selected as NSString).length
        return TextEdit(range: selection, replacement: "[\(selected)]()",
                        selection: NSRange(location: selection.location + len + 3, length: 0))
    }

    /// `[[Note]]`, an Obsidian link to another note.
    public static func wikilink(in text: String, selection: NSRange) -> TextEdit {
        let selected = (text as NSString).substring(with: selection)
        let len = (selected as NSString).length
        return TextEdit(range: selection, replacement: "[[\(selected)]]",
                        selection: NSRange(location: selection.location + 2, length: len))
    }

    /// Inserts a block on its own lines at the caret (replacing any selection). `caret` is where the
    /// cursor goes inside `block`; nil puts it at the end.
    public static func insertBlock(_ block: String, in text: String, selection: NSRange, caret: Int? = nil,
                                   selectLength: Int = 0) -> TextEdit {
        let ns = text as NSString
        var prefix = ""
        if selection.location > 0, ns.character(at: selection.location - 1) != 10 { prefix = "\n\n" }
        else if selection.location > 1, ns.character(at: selection.location - 2) != 10 { prefix = "\n" }
        var suffix = ""
        let end = NSMaxRange(selection)
        if end < ns.length, ns.character(at: end) != 10 { suffix = "\n" }
        let body = block.hasSuffix("\n") ? block : block + "\n"
        let replacement = prefix + body + suffix
        let start = selection.location + (prefix as NSString).length
        let caretAt = start + (caret ?? (body as NSString).length)
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: caretAt, length: selectLength))
    }

    /// Wraps the selected lines in a fenced code block (```language), or inserts an empty one with
    /// the caret inside.
    public static func codeBlock(in text: String, selection: NSRange, language: String = "") -> TextEdit {
        let ns = text as NSString
        let open = "```" + language
        let openLength = (open as NSString).length
        if selection.length == 0 {
            return insertBlock(open + "\n\n```\n", in: text, selection: selection,
                               caret: openLength + 1)
        }
        let r = linesRange(ns, selection)
        let inner = ns.substring(with: r)
        let replacement = open + "\n" + inner + "\n```"
        return TextEdit(range: r, replacement: replacement, selection: NSRange(location: r.location + openLength, length: 0))
    }

    // MARK: Code blocks

    public static let codeIndentUnit = "    "

    static func isFence(_ line: String) -> Bool {
        let t = line.drop { $0 == " " || $0 == "\t" }
        return t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    /// Number of fence lines that start before `location`'s line.
    private static func fencesBefore(_ ns: NSString, line lr: NSRange) -> Int {
        var count = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: lr.location), options: .byLines) { line, _, _, _ in
            if let line, isFence(line) { count += 1 }
        }
        return count
    }

    /// Whether `location` is on a line inside a fenced code block (not on the ``` lines themselves).
    public static func isInCodeBlock(_ text: String, at location: Int) -> Bool {
        let ns = text as NSString
        let lr = linesRange(ns, NSRange(location: min(location, ns.length), length: 0))
        if isFence(ns.substring(with: lr)) { return false }
        return fencesBefore(ns, line: lr) % 2 == 1
    }

    /// Return inside code: keep the indentation, indent one more level after `{ [ (` or a trailing `:`,
    /// and put a closing bracket right after the caret on its own line. Return at the end of an opening
    /// ```lang line that has no closing fence adds one.
    static func codeNewline(in text: String, at caret: Int) -> TextEdit? {
        let ns = text as NSString
        let lr = linesRange(ns, NSRange(location: caret, length: 0))
        let line = ns.substring(with: lr)
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })

        if isFence(line) {
            guard caret == NSMaxRange(lr), fencesBefore(ns, line: lr) % 2 == 0 else { return nil }
            // Opening fence: is there a closing one further down?
            var fencesAfter = 0
            let after = NSMaxRange(lr)
            ns.enumerateSubstrings(in: NSRange(location: after, length: ns.length - after), options: .byLines) { l, _, _, _ in
                if let l, isFence(l) { fencesAfter += 1 }
            }
            guard fencesAfter % 2 == 0 else { return nil } // already closed: plain newline
            let insertion = "\n" + indent + "\n" + indent + "```"
            return TextEdit(range: NSRange(location: caret, length: 0), replacement: insertion,
                            selection: NSRange(location: caret + 1 + (indent as NSString).length, length: 0))
        }

        guard fencesBefore(ns, line: lr) % 2 == 1 else { return nil }
        let before = ns.substring(with: NSRange(location: lr.location, length: caret - lr.location))
        let afterCaret = ns.substring(with: NSRange(location: caret, length: NSMaxRange(lr) - caret))
        let unit = indent.hasPrefix("\t") ? "\t" : codeIndentUnit
        let lastChar = before.trimmingCharacters(in: .whitespaces).last
        let opens = lastChar.map { "{[(".contains($0) || $0 == ":" } ?? false
        let pairs: [Character: Character] = ["{": "}", "[": "]", "(": ")"]
        let closesRightAfter = lastChar.flatMap { pairs[$0] }.map { afterCaret.trimmingCharacters(in: .whitespaces).first == $0 } ?? false

        let keptIndent = (before as NSString).length < (indent as NSString).length ? before : indent
        if closesRightAfter {
            let inner = "\n" + keptIndent + unit
            let replacement = inner + "\n" + keptIndent
            // Drop spaces between the caret and the closing bracket.
            let spaces = afterCaret.prefix { $0 == " " }.utf16.count
            return TextEdit(range: NSRange(location: caret, length: spaces), replacement: replacement,
                            selection: NSRange(location: caret + (inner as NSString).length, length: 0))
        }
        return insert("\n" + keptIndent + (opens ? unit : ""), at: caret)
    }

    /// Tab inside code inserts spaces (or indents the selected lines); Shift-Tab outdents.
    static func codeIndent(in text: String, selection: NSRange, outdent: Bool) -> TextEdit {
        if !outdent && selection.length == 0 { return insert(codeIndentUnit, at: selection.location) }
        return transformLines(text, selection) { lines in
            lines.map { line in
                if !outdent { return line.isEmpty ? line : codeIndentUnit + line }
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                return String(line.dropFirst(min(codeIndentUnit.count, line.prefix { $0 == " " }.count)))
            }
        }
    }
}
