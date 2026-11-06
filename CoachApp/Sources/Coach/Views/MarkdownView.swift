import SwiftUI

/// Lightweight block renderer for Obsidian-flavoured Markdown: headings, bullets, numbered lists, checkboxes,
/// quotes/callouts, code fences, rules and paragraphs. Inline bold/italic/code/links use AttributedString,
/// and `[[wikilinks]]` show their display text.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        let blocks = MDBlock.parse(markdown)
        if blocks.isEmpty {
            Text("This note is empty. Add your notes in Obsidian.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title.bold() : level == 2 ? .title2.bold() : level == 3 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 8 : 4)
        case .listItem(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                switch marker {
                case .bullet: Text("•").foregroundStyle(.secondary)
                case .number(let n): Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
                case .task(let done):
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.green : Color.secondary)
                }
                Text(Self.inline(text))
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .quote(let text):
            Text(Self.inline(text))
                .padding(.leading, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(.tint).frame(width: 3) }
                .background(Color.accentColor.opacity(0.06))
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        case .rule:
            Divider()
        case .paragraph(let text):
            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func inline(_ s: String) -> AttributedString {
        var text = s
        // [[target|alias]] → alias, [[target]] → target, ![[embed]] → embed name
        while let open = text.range(of: "[["), let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) {
            let inner = String(text[open.upperBound..<close.lowerBound])
            let shown = inner.split(separator: "|", maxSplits: 1).last.map(String.init) ?? inner
            var start = open.lowerBound
            if start > text.startIndex, text[text.index(before: start)] == "!" { start = text.index(before: start) }
            text.replaceSubrange(start..<close.upperBound, with: "**\(shown)**")
        }
        text = text.replacingOccurrences(of: "==", with: "")
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

enum MDBlock: Equatable {
    enum Marker: Equatable { case bullet, number(Int), task(Bool) }

    case heading(Int, String)
    case listItem(indent: Int, marker: Marker, text: String)
    case quote(String)
    case code(String)
    case rule
    case paragraph(String)

    static func parse(_ md: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }

        for raw in md.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }

            if trimmed.isEmpty { flush(); continue }

            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush()
                blocks.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1))))
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { flush(); blocks.append(.rule); continue }

            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty { flush() }
                var q = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                // Obsidian callout header: > [!note] Title  → Title
                if q.hasPrefix("[!"), let end = q.firstIndex(of: "]") {
                    let title = q[q.index(after: end)...].trimmingCharacters(in: .whitespaces)
                    q = title.isEmpty ? String(q[q.index(q.startIndex, offsetBy: 2)..<end]).capitalized : title
                    q = "**\(q)**"
                }
                quote.append(q)
                continue
            }

            let indent = (line.prefix(while: { $0 == " " }).count) / 2
            if let item = listItem(trimmed, indent: indent) { flush(); blocks.append(item); continue }

            if !quote.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func listItem(_ t: String, indent: Int) -> MDBlock? {
        for bullet in ["- ", "* ", "+ "] where t.hasPrefix(bullet) {
            let rest = String(t.dropFirst(2))
            if rest.hasPrefix("[ ] ") { return .listItem(indent: indent, marker: .task(false), text: String(rest.dropFirst(4))) }
            if rest.lowercased().hasPrefix("[x] ") { return .listItem(indent: indent, marker: .task(true), text: String(rest.dropFirst(4))) }
            return .listItem(indent: indent, marker: .bullet, text: rest)
        }
        let digits = t.prefix(while: \.isNumber)
        if !digits.isEmpty, let n = Int(digits), t.dropFirst(digits.count).hasPrefix(". ") {
            return .listItem(indent: indent, marker: .number(n), text: String(t.dropFirst(digits.count + 2)))
        }
        return nil
    }
}
