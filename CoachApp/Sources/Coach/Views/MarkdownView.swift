import CoachCore
import SwiftUI

/// Lightweight block renderer for Obsidian-flavoured Markdown: headings, bullets, numbered lists, checkboxes,
/// quotes/callouts, code fences, rules and paragraphs. Inline bold/italic/code/links use AttributedString,
/// and `[[wikilinks]]` show their display text.
struct MarkdownView: View {
    let markdown: String
    /// The note being shown, so `![[image.png]]` embeds can be found next to it.
    var noteURL: URL? = nil
    @Environment(VaultStore.self) private var store: VaultStore?

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
        case .code(let language, let text):
            CodeBlockView(language: language, code: text)
        case .image(let target, let width):
            NoteImageView(target: target, width: width,
                          url: store?.attachments?.resolve(target, from: noteURL))
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
    case code(language: String?, String)
    case image(target: String, width: CGFloat?)
    case rule
    case paragraph(String)

    static func parse(_ md: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var code: [String]?
        var codeLanguage: String?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }

        for raw in md.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let c = code {
                    blocks.append(.code(language: codeLanguage, c.joined(separator: "\n"))); code = nil
                } else {
                    flush(); code = []; codeLanguage = CodeSyntax.fenceLanguage(trimmed)
                }
                continue
            }
            if code != nil { code!.append(raw); continue }

            if let image = image(trimmed) { flush(); blocks.append(image); continue }

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
        if let c = code { blocks.append(.code(language: codeLanguage, c.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// A line that is just an image: `![[shot.png]]`, `![[shot.png|300]]` or `![alt](path.png)`.
    private static func image(_ t: String) -> MDBlock? {
        if t.hasPrefix("![["), t.hasSuffix("]]") {
            let inner = t.dropFirst(3).dropLast(2)
            guard !inner.contains("]") else { return nil }
            let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
            guard let target = parts.first, AttachmentStore.isImage(target) else { return nil }
            let width = parts.count > 1 ? Double(parts[1].split(separator: "x").first ?? "").map { CGFloat($0) } : nil
            return .image(target: target, width: width)
        }
        if t.hasPrefix("!["), t.hasSuffix(")"), let mid = t.range(of: "](") {
            var target = String(t[mid.upperBound..<t.index(before: t.endIndex)])
            if let space = target.firstIndex(of: " "), !target.hasPrefix("<") { target = String(target[..<space]) }
            return target.isEmpty || t[t.index(t.startIndex, offsetBy: 2)..<mid.lowerBound].contains("]") ? nil
                : .image(target: target, width: nil)
        }
        return nil
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

/// A fenced code block with syntax colours, its language and a Copy button.
struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(Self.highlighted(code, language: language))
                .font(.system(.callout, design: .monospaced))
                .lineSpacing(2)
                .fixedSize(horizontal: true, vertical: false)
                .padding(12)
                .padding(.top, language == nil ? 0 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: CodeTheme.blockBackground), in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                if let language { Text(language.lowercased()).foregroundStyle(.tertiary) }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .font(.caption)
            .padding(6)
        }
    }

    static func highlighted(_ code: String, language: String?) -> AttributedString {
        var out = AttributedString(code)
        for token in CodeSyntax.tokens(code, language: language) {
            guard let r = Range(token.range, in: code),
                  let lo = AttributedString.Index(r.lowerBound, within: out),
                  let hi = AttributedString.Index(r.upperBound, within: out) else { continue }
            out[lo..<hi].foregroundColor = Color(nsColor: CodeTheme.color(token.kind))
            if CodeTheme.isBold(token.kind) { out[lo..<hi].font = .system(.callout, design: .monospaced).weight(.semibold) }
        }
        return out
    }
}

/// An embedded image. Double-click opens it in Preview.
struct NoteImageView: View {
    let target: String
    let width: CGFloat?
    let url: URL?

    var body: some View {
        if let remote = URL(string: target), ["http", "https"].contains(remote.scheme?.lowercased() ?? "") {
            AsyncImage(url: remote) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().frame(maxWidth: width ?? 640, maxHeight: 520, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if phase.error != nil {
                    missing
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        } else if let url, let image = ImageCache.image(at: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: min(width ?? image.size.width, 640), maxHeight: 520, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                .help("\(url.lastPathComponent). Double-click to open")
        } else {
            missing
        }
    }

    private var missing: some View {
        Label("Image not found: \(target)", systemImage: "photo.badge.exclamationmark")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
