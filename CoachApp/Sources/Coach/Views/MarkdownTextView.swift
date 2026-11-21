import AppKit
import CoachCore
import SwiftUI

extension NSAttributedString.Key {
    /// Code (inline or block): no spell checking.
    static let coachCode = NSAttributedString.Key("coachCode")
    /// A fenced code block: drawn with a full-width background.
    static let coachCodeBlock = NSAttributedString.Key("coachCodeBlock")
    /// An image embed on its own line: the image is drawn below it.
    static let coachImage = NSAttributedString.Key("coachImage")
}

/// An image shown under its `![[embed]]` line in the editor.
final class EditorImage: NSObject {
    let image: NSImage
    let size: NSSize
    init(image: NSImage, size: NSSize) { self.image = image; self.size = size }
}

/// Code colours, Xcode-like, for light and dark mode.
enum CodeTheme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func c(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? c(dark) : c(light) }
    }
    static let keyword = dynamic(0xAD3DA4, 0xFC5FA3)
    static let string = dynamic(0xC41A16, 0xFC6A5D)
    static let comment = dynamic(0x6C7986, 0x7F8C98)
    static let number = dynamic(0x1C00CF, 0xD0BF69)
    static let type = dynamic(0x0B4F79, 0x5DD8FF)
    static let function = dynamic(0x326D74, 0x67B7A4)
    static let attribute = dynamic(0x815F03, 0xFD8F3F)
    static let tag = dynamic(0x0B4F79, 0x5DD8FF)

    static func color(_ kind: CodeTokenKind) -> NSColor {
        switch kind {
        case .keyword, .constant: keyword
        case .string: string
        case .comment: comment
        case .number: number
        case .type: type
        case .function: function
        case .attribute: attribute
        case .tag: tag
        }
    }
    static func isBold(_ kind: CodeTokenKind) -> Bool { kind == .keyword || kind == .constant }
    static let blockBackground = NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.045)
    }
}

/// Styles Markdown in place while you type: headings large, **bold** bold, `code` monospaced,
/// links coloured, syntax characters faded. The text itself stays plain Markdown.
enum MarkdownHighlighter {
    static let baseSize: CGFloat = 14.5
    static let headingSizes: [CGFloat] = [24, 20, 17.5, 16, 15, 14.5]

    static var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    static var monoFont: NSFont { .monospacedSystemFont(ofSize: baseSize - 1.5, weight: .regular) }
    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 5
        return p
    }()
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static func re(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }
    private static let fence = re(#"^[ \t]*(```|~~~)"#)
    private static let inlineCode = re(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let heading = re(#"^(#{1,6})[ \t]+.*$"#)
    private static let quote = re(#"^[ \t]*>.*$"#)
    private static let callout = re(#"^[ \t]*>[ \t]*\[![^\]\n]+\][^\n]*"#)
    private static let listMarker = re(#"^[ \t]*([-*+]|\d{1,9}[.)])(?= )"#)
    private static let task = re(#"^[ \t]*[-*+] (\[[ xX]\])"#)
    private static let doneTask = re(#"^[ \t]*[-*+] \[[xX]\] (.*)$"#)
    private static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = re(#"(?<![*\w])(\*|_)(?![*\s])(.+?)(?<![*\s])\1(?![*\w])"#)
    private static let strike = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let mark = re(#"==(?=\S)(.+?)(?<=\S)=="#)
    private static let wikilink = re(#"!?\[\[([^\]\n]+)\]\]"#)
    private static let mdLink = re(#"!?\[([^\]\n]*)\]\(([^)\n]+)\)"#)
    private static let rule = re(#"^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$"#)
    private static let tag = re(#"(?<![\w#&/])#[A-Za-z][\w/-]*"#)
    private static let wikiImage = re(#"^[ \t]*!\[\[([^\]|\n]+)(?:\|(\d+)(?:x\d+)?)?\]\][ \t]*$"#)
    private static let mdImage = re(#"^[ \t]*!\[[^\]\n]*\]\((<[^>\n]+>|[^)\s]+)(?:[ \t]+"[^"\n]*")?\)[ \t]*$"#)
    static var monoBold: NSFont { .monospacedSystemFont(ofSize: baseSize - 1.5, weight: .semibold) }
    static let codeParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        return p
    }()

    /// Display size for an image in a column `width` wide (Obsidian's `|300` sets the width).
    static func displaySize(_ image: NSImage, requestedWidth: CGFloat?, columnWidth: CGFloat) -> NSSize {
        let natural = image.size
        var w = min(requestedWidth ?? natural.width, columnWidth, 640)
        var h = natural.height * w / max(natural.width, 1)
        if h > 460 { w *= 460 / h; h = 460 }
        return NSSize(width: max(1, w.rounded()), height: max(1, h.rounded()))
    }

    /// `images` finds the picture for an embed target; `columnWidth` is the width images can use.
    static func highlight(_ storage: NSTextStorage, images: ((String) -> NSImage?)? = nil, columnWidth: CGFloat = 600) {
        let s = storage.string
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        storage.setAttributes(baseAttributes, range: full)
        guard full.length > 0 else { return }

        var code = IndexSet()
        func isCode(_ r: NSRange) -> Bool { code.intersects(integersIn: r.location..<NSMaxRange(r)) }
        func each(_ regex: NSRegularExpression, skipCode: Bool = true, _ body: (NSTextCheckingResult) -> Void) {
            regex.enumerateMatches(in: s, range: full) { m, _, _ in
                guard let m, !(skipCode && isCode(m.range)) else { return }
                body(m)
            }
        }
        func color(_ c: NSColor, _ r: NSRange) { if r.location != NSNotFound { storage.addAttribute(.foregroundColor, value: c, range: r) } }
        func fade(_ r: NSRange) { color(.tertiaryLabelColor, r) }
        func trait(_ t: NSFontDescriptor.SymbolicTraits, _ r: NSRange) {
            storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                let f = (value as? NSFont) ?? baseFont
                let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(t))
                storage.addAttribute(.font, value: NSFont(descriptor: d, size: f.pointSize) ?? f, range: sub)
            }
        }
        let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)

        // Fenced code blocks: monospaced, full-width background, syntax colours for the ```language.
        var blocks: [(block: NSRange, open: NSRange, content: NSRange)] = []
        var openFence: NSRange?
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, line, enclosing, _ in
            guard fence.firstMatch(in: s, range: line) != nil else { return }
            if let open = openFence {
                let contentStart = NSMaxRange(open)
                blocks.append((NSRange(location: open.location, length: NSMaxRange(enclosing) - open.location), open,
                               NSRange(location: contentStart, length: max(0, line.location - contentStart))))
                openFence = nil
            } else {
                openFence = enclosing
            }
        }
        if let open = openFence { // unclosed: style to the end
            blocks.append((NSRange(location: open.location, length: full.length - open.location), open,
                           NSRange(location: NSMaxRange(open), length: max(0, full.length - NSMaxRange(open)))))
        }
        for b in blocks {
            code.insert(integersIn: b.block.location..<NSMaxRange(b.block))
            storage.addAttributes([.font: monoFont, .paragraphStyle: codeParagraph, .coachCode: true, .coachCodeBlock: true],
                                  range: b.block)
            let openLine = ns.substring(with: b.open)
            fade(b.open)
            if let lang = CodeSyntax.fenceLanguage(openLine) {
                color(.secondaryLabelColor, ns.range(of: lang, range: b.open))
            }
            let closeStart = NSMaxRange(b.content)
            if closeStart < NSMaxRange(b.block) { fade(NSRange(location: closeStart, length: NSMaxRange(b.block) - closeStart)) }
            guard b.content.length > 0 else { continue }
            let lang = CodeSyntax.fenceLanguage(openLine)
            for t in CodeSyntax.tokens(ns.substring(with: b.content), language: lang) {
                let r = NSRange(location: b.content.location + t.range.location, length: t.range.length)
                storage.addAttribute(.foregroundColor, value: CodeTheme.color(t.kind), range: r)
                if CodeTheme.isBold(t.kind) { storage.addAttribute(.font, value: monoBold, range: r) }
            }
        }

        // Inline code.
        each(inlineCode) { m in
            storage.addAttributes([.font: monoFont, .backgroundColor: codeBackground, .coachCode: true], range: m.range)
            fade(NSRange(location: m.range.location, length: m.range(at: 1).length))
            fade(NSRange(location: NSMaxRange(m.range) - m.range(at: 1).length, length: m.range(at: 1).length))
            code.insert(integersIn: m.range.location..<NSMaxRange(m.range))
        }

        each(heading) { m in
            let level = m.range(at: 1).length
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: headingSizes[level - 1], weight: level <= 2 ? .bold : .semibold), range: m.range)
            fade(NSRange(location: m.range(at: 1).location, length: m.range(at: 1).length + 1))
        }
        each(quote) { m in
            color(.secondaryLabelColor, m.range)
            if let gt = (ns.substring(with: m.range) as NSString).range(of: ">").nilIfNotFound {
                fade(NSRange(location: m.range.location + gt.location, length: 1))
            }
        }
        each(callout) { m in
            color(.controlAccentColor, m.range)
            trait(.bold, m.range)
        }
        each(listMarker) { m in
            color(.controlAccentColor, m.range(at: 1))
            trait(.bold, m.range(at: 1))
        }
        each(task) { m in color(.controlAccentColor, m.range(at: 1)) }
        each(doneTask) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            color(.secondaryLabelColor, m.range(at: 1))
        }
        each(bold) { m in
            trait(.bold, m.range)
            let l = m.range(at: 1).length
            fade(NSRange(location: m.range.location, length: l))
            fade(NSRange(location: NSMaxRange(m.range) - l, length: l))
        }
        each(italic) { m in
            trait(.italic, m.range)
            fade(NSRange(location: m.range.location, length: 1))
            fade(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        each(strike) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            fade(NSRange(location: m.range.location, length: 2))
            fade(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        each(mark) { m in
            storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: m.range(at: 1))
            fade(NSRange(location: m.range.location, length: 2))
            fade(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        each(wikilink) { m in
            fade(m.range)
            color(.linkColor, m.range(at: 1))
        }
        each(mdLink) { m in
            fade(m.range)
            color(.linkColor, m.range(at: 1))
        }
        each(rule) { m in fade(m.range) }
        each(tag) { m in color(.controlAccentColor, m.range) }

        // Images on their own line: make room below the line; the text view draws the picture there.
        guard let images else { return }
        func showImage(_ m: NSTextCheckingResult, target: String, width: CGFloat?) {
            guard let image = images(target) else { return }
            let size = displaySize(image, requestedWidth: width, columnWidth: columnWidth)
            let p = (paragraph.mutableCopy() as! NSMutableParagraphStyle)
            p.paragraphSpacing = size.height + 16
            storage.addAttribute(.paragraphStyle, value: p, range: ns.lineRange(for: m.range))
            storage.addAttribute(.coachImage, value: EditorImage(image: image, size: size), range: m.range)
        }
        each(wikiImage) { m in
            let target = ns.substring(with: m.range(at: 1))
            guard AttachmentStore.isImage(target) else { return }
            let width = m.range(at: 2).location == NSNotFound ? nil : Double(ns.substring(with: m.range(at: 2))).map { CGFloat($0) }
            showImage(m, target: target, width: width)
        }
        each(mdImage) { m in showImage(m, target: ns.substring(with: m.range(at: 1)), width: nil) }
    }
}

private extension NSRange {
    var nilIfNotFound: NSRange? { location == NSNotFound ? nil : self }
}

/// The text view: Markdown styling, smart lists, formatting shortcuts, find bar, centred column.
final class MarkdownNSTextView: NSTextView {
    static let maxColumnWidth: CGFloat = 760

    /// Saves a pasted/dropped image and returns the name to embed (nil if it couldn't be saved).
    var saveImage: ((PasteboardImages.Item) -> String?)?
    /// Finds the image for an embed target.
    var lookUpImage: ((String) -> NSImage?)?

    /// Width images can use: the text column.
    var columnWidth: CGFloat {
        guard let tc = textContainer, tc.size.width > 100 else { return 600 }
        return tc.size.width - 2 * tc.lineFragmentPadding
    }

    /// Restyles after every edit (typing, paste, undo, formatting commands), once the edit is complete.
    /// Styling must not happen while the storage is still processing the edit: restyling the whole text
    /// there widens the edited range to the whole note, and AppKit then moves the caret to its end.
    override func didChangeText() {
        if !hasMarkedText() { restyle() } // composing (e.g. accents): restyled when the text is committed
        super.didChangeText()
    }

    /// Replaces all the text (e.g. reloaded from disk), keeping the caret where it was as far as possible.
    func replaceAllText(_ text: String) {
        let sel = selectedRange()
        string = text
        restyle()
        let len = (text as NSString).length
        setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
    }

    /// Re-applies styling (e.g. after a resize, so images fit the new width). Changes attributes only,
    /// so the text and the caret stay put.
    func restyle() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        MarkdownHighlighter.highlight(storage, images: lookUpImage, columnWidth: columnWidth)
        storage.endEditing()
    }
    private var restylePending = false
    private var styledWidth: CGFloat = 0
    private func restyleSoonIfWidthChanged() {
        let width = columnWidth
        guard abs(width - styledWidth) > 1, !restylePending else { return }
        styledWidth = width
        guard textStorage?.string.contains("![") == true else { return }
        restylePending = true
        DispatchQueue.main.async { [weak self] in
            self?.restylePending = false
            self?.restyle()
        }
    }

    // MARK: Images: paste and drop

    private func insertImages(from pb: NSPasteboard, at range: NSRange) -> Bool {
        let items = PasteboardImages.items(on: pb)
        guard !items.isEmpty, let saveImage else { return false }
        let names = items.compactMap(saveImage)
        guard !names.isEmpty else { NSSound.beep(); return true }
        let embeds = names.map { "![[\($0)]]" }.joined(separator: "\n")
        apply(MarkdownEditing.insertBlock(embeds, in: string, selection: range))
        return true
    }

    override func paste(_ sender: Any?) {
        if insertImages(from: .general, at: selectedRange()) { return }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingEntered(sender)
        return PasteboardImages.hasImages(sender.draggingPasteboard) ? .copy : op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingUpdated(sender)
        return PasteboardImages.hasImages(sender.draggingPasteboard) ? .copy : op
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if PasteboardImages.hasImages(pb) {
            let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            window?.makeFirstResponder(self)
            if insertImages(from: pb, at: NSRange(location: index, length: 0)) { return true }
        }
        return super.performDragOperation(sender)
    }

    // MARK: Drawing: code block backgrounds and images

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let storage = textStorage, let lm = layoutManager, let tc = textContainer, storage.length > 0 else { return }
        let origin = textContainerOrigin
        CodeTheme.blockBackground.setFill()
        storage.enumerateAttribute(.coachCodeBlock, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let bounds = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            let box = NSRect(x: origin.x + tc.lineFragmentPadding - 8, y: origin.y + bounds.minY - 4,
                             width: columnWidth + 16, height: bounds.height + 8)
            guard box.intersects(rect) else { return }
            NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let storage = textStorage, let lm = layoutManager, let tc = textContainer, storage.length > 0 else { return }
        let origin = textContainerOrigin
        storage.enumerateAttribute(.coachImage, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let item = value as? EditorImage else { return }
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = lm.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            let frame = NSRect(x: origin.x + tc.lineFragmentPadding, y: origin.y + line.maxY + 6,
                               width: item.size.width, height: item.size.height)
            guard frame.intersects(dirtyRect) else { return }
            NSGraphicsContext.saveGraphicsState()
            let shape = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
            shape.addClip()
            item.image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.separatorColor.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
    }

    /// No red squiggles under code.
    override func setSpellingState(_ value: Int, range charRange: NSRange) {
        if value != 0, let storage = textStorage, charRange.location < storage.length,
           storage.attribute(.coachCode, at: charRange.location, effectiveRange: nil) != nil {
            return
        }
        super.setSpellingState(value, range: charRange)
    }

    func apply(_ edit: TextEdit) {
        guard edit.range.location != NSNotFound, NSMaxRange(edit.range) <= (string as NSString).length else { return }
        breakUndoCoalescing()
        if shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()
            setSelectedRange(edit.selection)
            scrollRangeToVisible(edit.selection)
        }
    }

    // Commands (toolbar and shortcuts).
    func wrap(_ marker: String) { apply(MarkdownEditing.toggleWrap(marker, in: string, selection: selectedRange())) }
    func heading(_ level: Int) { apply(MarkdownEditing.setHeading(level, in: string, selection: selectedRange())) }
    func lineStyle(_ style: MarkdownEditing.LineStyle) { apply(MarkdownEditing.toggleLineStyle(style, in: string, selection: selectedRange())) }
    func link() { apply(MarkdownEditing.link(in: string, selection: selectedRange())) }
    func wikilink() { apply(MarkdownEditing.wikilink(in: string, selection: selectedRange())) }
    func codeBlock(_ language: String = "") {
        apply(MarkdownEditing.codeBlock(in: string, selection: selectedRange(), language: language))
    }
    /// Lets you pick image files and embeds them, like pasting them.
    func insertImageFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to add to this note"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let pb = NSPasteboard(name: NSPasteboard.Name("coach.insertImage"))
        pb.clearContents()
        pb.writeObjects(panel.urls as [NSURL])
        _ = insertImages(from: pb, at: selectedRange())
    }
    func block(_ text: String, caret: Int? = nil, select: Int = 0) {
        apply(MarkdownEditing.insertBlock(text, in: string, selection: selectedRange(), caret: caret, selectLength: select))
    }
    func showFind() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        performTextFinderAction(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText() else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.characters(byApplyingModifiers: [])?.lowercased() ?? ""
        switch (flags, key) {
        case ([.command], "b"): wrap("**")
        case ([.command], "i"): wrap("*")
        case ([.command], "e"): wrap("`")
        case ([.command], "k"): link()
        case ([.command, .shift], "k"): wikilink()
        case ([.command, .shift], "x"): wrap("~~")
        case ([.command, .shift], "h"): wrap("==")
        case ([.command, .shift], "7"): lineStyle(.numbered)
        case ([.command, .shift], "8"): lineStyle(.bullet)
        case ([.command, .shift], "9"): lineStyle(.task)
        case ([.command, .shift], "."): lineStyle(.quote)
        case ([.command, .option], "1"), ([.command, .option], "2"), ([.command, .option], "3"): heading(Int(key)!)
        case ([.command, .option], "0"): heading(0)
        case ([.command, .option], "c"): codeBlock()
        case ([.command], "f"): showFind()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Keeps lines a comfortable length on wide windows.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = max(22, (newSize.width - Self.maxColumnWidth) / 2)
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: 20)
        }
        restyleSoonIfWidthChanged()
    }
}

/// Gives SwiftUI buttons a handle on the text view.
@MainActor
final class MarkdownEditorController {
    weak var textView: MarkdownNSTextView?

    func run(_ action: (MarkdownNSTextView) -> Void) {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        action(tv)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var saveImage: ((PasteboardImages.Item) -> String?)?
    var lookUpImage: ((String) -> NSImage?)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 for predictable attribute styling. The coordinator keeps the storage alive.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        context.coordinator.storage = storage

        let tv = MarkdownNSTextView(frame: .zero, textContainer: container)
        tv.saveImage = saveImage
        tv.lookUpImage = lookUpImage
        context.coordinator.textView = tv
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.importsGraphics = false // images are saved as files and embedded instead (see paste)
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.typingAttributes = MarkdownHighlighter.baseAttributes
        tv.textContainerInset = NSSize(width: 22, height: 20)
        tv.delegate = context.coordinator
        tv.updateDragTypeRegistration()
        tv.string = text
        tv.restyle()
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = tv
        controller.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? MarkdownNSTextView else { return }
        controller.textView = tv
        tv.saveImage = saveImage
        tv.lookUpImage = lookUpImage
        // Replaced from outside (reloaded from disk). A value we sent up ourselves can arrive late while
        // you type; writing it back would undo keystrokes and move the cursor, so it's skipped.
        if tv.string != text, text != context.coordinator.lastSent {
            context.coordinator.lastSent = text
            tv.replaceAllText(text)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var storage: NSTextStorage?
        weak var textView: MarkdownNSTextView?
        /// The text last passed to the binding from the text view.
        var lastSent: String?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            lastSent = tv.string
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let tv = textView as? MarkdownNSTextView, !tv.hasMarkedText() else { return false }
            let sel = tv.selectedRange()
            let edit: TextEdit?
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                edit = sel.length == 0 ? MarkdownEditing.newline(in: tv.string, at: sel.location) : nil
            case #selector(NSResponder.insertTab(_:)):
                edit = MarkdownEditing.indent(in: tv.string, selection: sel, outdent: false)
            case #selector(NSResponder.insertBacktab(_:)):
                edit = MarkdownEditing.indent(in: tv.string, selection: sel, outdent: true)
            default:
                edit = nil
            }
            guard let edit else { return false }
            tv.apply(edit)
            return true
        }
    }
}
