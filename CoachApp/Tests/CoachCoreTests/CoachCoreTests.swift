import Foundation
import Testing
@testable import CoachCore

@Suite struct NoteDocumentTests {
    @Test func preservesUnrelatedFrontmatterAndBody() {
        let text = """
        ---
        title: My note
        tags:
          - dsa
          - trees
        # a comment
        ---
        # Heading

        Body text.
        """
        var doc = NoteDocument(text: text)
        doc.set(CoachKey.id, "abc")
        doc.set(CoachKey.confidence, "2")
        let out = doc.render()
        #expect(out.contains("title: My note\ntags:\n  - dsa\n  - trees\n# a comment\ncoach_id: abc\ncoach_confidence: 2\n---\n# Heading"))
        #expect(NoteDocument(text: out).value(for: CoachKey.confidence) == "2")
    }

    @Test func roundTripIsLossless() {
        let text = "---\na: 1\nb: \"x: y\"\n---\nhello\n"
        #expect(NoteDocument(text: text).render() == text)
        let crlf = "---\r\na: 1\r\n---\r\nhello\r\n"
        #expect(NoteDocument(text: crlf).render() == crlf)
        let plain = "no frontmatter\n"
        #expect(NoteDocument(text: plain).render() == plain)
    }

    @Test func addsFrontmatterToPlainNote() {
        var doc = NoteDocument(text: "# Title\n")
        doc.set(CoachKey.id, "x")
        #expect(doc.render() == "---\ncoach_id: x\n---\n# Title\n")
    }

    @Test func replacesAndRemovesKeysIncludingListValues() {
        var doc = NoteDocument(text: "---\ncoach_subject:\n  - a\n  - b\nother: 1\n---\n")
        doc.set(CoachKey.subject, "DSA", quoted: true)
        #expect(doc.render() == "---\ncoach_subject: \"DSA\"\nother: 1\n---\n")
        doc.set(CoachKey.subject, nil)
        #expect(doc.render() == "---\nother: 1\n---\n")
    }

    @Test func quotingRoundTrips() {
        var doc = NoteDocument(text: "")
        doc.set("k", #"He said "hi": \ ok"#, quoted: true)
        #expect(NoteDocument(text: doc.render()).value(for: "k") == #"He said "hi": \ ok"#)
    }

    @Test func appendsToReviewLog() {
        var doc = NoteDocument(text: "# T\n\n## Review log\n- one\n\n## Later\ntext\n")
        doc.appendLine("- two", toSection: "## Review log")
        #expect(doc.body == "# T\n\n## Review log\n- one\n- two\n\n## Later\ntext\n")

        var fresh = NoteDocument(text: "# T\n\nNotes.\n")
        fresh.appendLine("- first", toSection: "## Review log")
        #expect(fresh.body == "# T\n\nNotes.\n\n## Review log\n- first\n")
    }

    @Test func readsSection() {
        let doc = NoteDocument(text: "## Recall question\nWhat is a BST?\n\n## Notes\nx")
        #expect(doc.section("## Recall question") == "What is a BST?")
    }
}

@Suite struct SchedulerTests {
    let cal = Calendar.current
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func days(_ d: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: now), to: d).day! }

    @Test func lowConfidenceComesBackSooner() {
        let gaps = (1...5).map { days(Scheduler.afterReview(confidence: $0, previousStreak: 0, reviewedAt: now).nextReview) }
        #expect(gaps == [1, 2, 4, 7, 14])
    }

    @Test func streakGrowsIntervalAndWeakRatingResetsIt() {
        let r1 = Scheduler.afterReview(confidence: 3, previousStreak: 3, reviewedAt: now)
        #expect(r1.streak == 4)
        #expect(days(r1.nextReview) == 16) // 4 × 1.6³ = 16.4
        let r2 = Scheduler.afterReview(confidence: 2, previousStreak: 5, reviewedAt: now)
        #expect(r2.streak == 0)
        #expect(days(r2.nextReview) == 2)
    }

    @Test func criticalTopicsAreCapped() {
        #expect(Scheduler.intervalDays(confidence: 1, streak: 10) == 5)
        #expect(Scheduler.intervalDays(confidence: 5, streak: 10) == 180)
    }

    @Test func firstReviewIsHalfTheGap() {
        let gaps = (1...5).map { days(Scheduler.firstReview(confidence: $0, addedAt: now)) }
        #expect(gaps == [1, 1, 2, 4, 7])
    }
}

@Suite struct TopicTests {
    @Test func parsesTopic() throws {
        let text = """
        ---
        coach_id: 123
        coach_confidence: 1
        coach_created: 2026-11-05T14:32:00+05:30
        coach_next_review: 2026-11-07
        coach_review_count: 4
        ---
        """
        let t = try #require(Topic(document: NoteDocument(text: text),
                                   url: URL(fileURLWithPath: "/v/Coach/OS/Memory/Paging.md"),
                                   coachRoot: URL(fileURLWithPath: "/v/Coach")))
        #expect(t.title == "Paging")
        #expect(t.folder == ["OS", "Memory"])
        #expect(t.subjectName == "OS")
        #expect(t.folderDisplay == "OS › Memory")
        #expect(t.isInside(["OS"]) && t.isInside([]) && !t.isInside(["DSA"]))
        #expect(t.confidence == 1)
        #expect(t.reviewCount == 4)
        #expect(CoachDates.day(t.nextReview) == "2026-11-07")
        #expect(t.created != nil)
    }

    @Test func untrackedNoteIsNotATopic() {
        #expect(Topic(document: NoteDocument(text: "---\ntitle: x\n---\n"), url: URL(fileURLWithPath: "/a.md")) == nil)
    }

    @Test func scannerFindsTopicsSkipsHiddenAndFlagsDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Coach/DSA"), withIntermediateDirectories: true)
        try "---\ncoach_id: a\n---\n".write(to: root.appendingPathComponent("Coach/DSA/Heap.md"), atomically: true, encoding: .utf8)
        try "---\ncoach_id: a\n---\n".write(to: root.appendingPathComponent("Copy.md"), atomically: true, encoding: .utf8)
        try "plain".write(to: root.appendingPathComponent("Plain.md"), atomically: true, encoding: .utf8)
        try "---\ncoach_id: z\n---\n".write(to: root.appendingPathComponent(".obsidian/x.md"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Coach/Empty"), withIntermediateDirectories: true)
        let r = VaultScanner.scan(root: root)
        #expect(r.topics.count == 1)
        #expect(r.topics.first?.folder == ["Coach", "DSA"])
        #expect(Set(r.folders) == [["Coach"], ["Coach", "DSA"], ["Coach", "Empty"]])
        #expect(r.duplicateIDs.count == 1)
        #expect(r.untracked.map(\.lastPathComponent) == ["Plain.md"])
    }

    @Test func sanitizesFileNames() {
        #expect(VaultScanner.sanitizeFileName("  A/B: C#? ") == "A-B- C--")
    }
}

@Suite struct ReviewLogTests {
    @Test func parsesEntriesAndConfidence() {
        let doc = NoteDocument(text: """
        # T

        ## Review log
        - 2026-11-01 18:00 · added (confidence 2)
        - 2026-11-03 09:10 · reviewed · confidence 4 · 6 min · next 2026-11-10
        - 2026-11-04 10:00 · confidence 4 → 1
        - 2026-11-05 10:00 · postponed to 2026-11-06
        not a log line
        """)
        let e = ReviewLog.entries(in: doc)
        #expect(e.count == 4)
        #expect(e.map(\.confidence) == [2, 4, 1, nil])
        #expect(e.map(\.isReview) == [false, true, false, false])
        #expect(e[1].text == "reviewed · confidence 4 · 6 min · next 2026-11-10")
    }

    @Test func stripsSectionsAndTitle() {
        let doc = NoteDocument(text: "# Heaps\n\n## Recall question\nQ?\n\n## Notes\n- a\n\n## Review log\n- x\n")
        #expect(doc.body(removingSections: [CoachKey.recallHeading, CoachKey.reviewLogHeading], title: "Heaps") == "## Notes\n- a")
    }
}


@Suite struct FolderTreeTests {
    let root = URL(fileURLWithPath: "/v/Coach")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func topic(_ path: String, confidence: Int, dueInDays: Int, revised: Bool = true) -> Topic {
        let next = Calendar.current.date(byAdding: .day, value: dueInDays, to: now)!
        let text = """
        ---
        coach_id: \(path)
        coach_confidence: \(confidence)
        coach_next_review: \(CoachDates.day(next))
        \(revised ? "coach_last_reviewed: \(CoachDates.dateTime(now))" : "")
        ---
        """
        return Topic(document: NoteDocument(text: text), url: root.appendingPathComponent(path), coachRoot: root)!
    }

    @Test func rollsUpStatisticsFromFilesOnly() throws {
        let topics = [
            topic("DSA/Graphs/Shortest Paths/Dijkstra.md", confidence: 1, dueInDays: -2),
            topic("DSA/Graphs/Shortest Paths/Bellman-Ford.md", confidence: 2, dueInDays: 0, revised: false),
            topic("DSA/Graphs/BFS.md", confidence: 4, dueInDays: 9),
            topic("DSA/Arrays.md", confidence: 5, dueInDays: 20),
        ]
        let tree = FolderTree.build(rootName: "Coach", root: root, topics: topics,
                                    untracked: [root.appendingPathComponent("DSA/Graphs/Draft.md")],
                                    folders: [["DSA"], ["DSA", "Graphs"], ["DSA", "Graphs", "Shortest Paths"], ["OS"]])

        #expect(tree.children.map(\.name) == ["DSA", "OS"])
        let graphs = try #require(tree.node(at: ["DSA", "Graphs"]))
        #expect(graphs.files.map(\.title) == ["BFS"])
        #expect(graphs.children.map(\.name) == ["Shortest Paths"])

        let g = graphs.stats(now: now)
        #expect(g.fileCount == 3)
        #expect(g.averageConfidence == 7.0 / 3.0)
        #expect(g.distribution == [1, 1, 0, 1, 0])
        #expect(g.dueCount == 2)
        #expect(g.overdueCount == 1)
        #expect(g.neverRevisedCount == 1)
        #expect(g.untrackedCount == 1)
        #expect(g.coverage == 0.75)
        #expect(g.weakest.map(\.title) == ["Dijkstra", "Bellman-Ford", "BFS"])

        #expect(tree.stats(now: now).averageConfidence == 3.0)
        #expect(tree.node(at: ["OS"])?.stats(now: now).averageConfidence == nil)
        #expect(tree.flattened.map(\.path) == [[], ["DSA"], ["DSA", "Graphs"], ["DSA", "Graphs", "Shortest Paths"], ["OS"]])
    }
}

@Suite struct BatchInputTests {
    @Test func parsesLinesConfidenceAndListMarkers() {
        let items = BatchInput.parse("""
        BFS
        - Dijkstra | 1

          * Bellman-Ford |2
        A | B
        Topo sort | 9
        """, defaultConfidence: 3)
        #expect(items.map(\.title) == ["BFS", "Dijkstra", "Bellman-Ford", "A | B", "Topo sort | 9"])
        #expect(items.map(\.confidence) == [3, 1, 2, 3, 3])
    }
}

@Suite struct EditableNoteTests {
    let original = """
    ---
    title: keep me
    coach_confidence: 2
    ---
    # Dijkstra

    ## Recall question
    Why no negative edges?

    ## Notes
    Old text

    ## Review log
    - 2026-11-01 09:00 · added (confidence 2)

    ## Recall attempts
    - 2026-11-02 · greedy pick
    """

    @Test func readsEditableParts() {
        let e = NoteDocument(text: original).editable
        #expect(e.recallQuestion == "Why no negative edges?")
        #expect(e.content == "# Dijkstra\n\n## Notes\nOld text")
    }

    /// Text right under the recall question (no heading between) stays in the note, and saving
    /// without a recall question leaves the note exactly as typed.
    @Test func roundTripKeepsNoteText() {
        for (q, content) in [("Why?", "# Dijkstra\nline one\n\nline two"), ("Why?", "intro\nmore"), ("", "# Dijkstra\nline one")] {
            var doc = NoteDocument(text: original)
            doc.applyEditable(EditableNote(recallQuestion: q, content: content))
            let back = NoteDocument(text: doc.render()).editable
            #expect(back.recallQuestion == q)
            #expect(back.content.replacingOccurrences(of: "\n\n", with: "\n") == content.replacingOccurrences(of: "\n\n", with: "\n"))
            if q.isEmpty { #expect(back.content == content) }
            var again = NoteDocument(text: doc.render())
            again.applyEditable(back)
            #expect(again.render() == doc.render())
        }
    }

    @Test func savesTextAndKeepsCoachData() {
        var doc = NoteDocument(text: original)
        doc.applyEditable(EditableNote(recallQuestion: "How does relaxation work?",
                                       content: "# Dijkstra\n\n## Key points\n- min-heap\n"))
        let reread = NoteDocument(text: doc.render())
        #expect(reread.value(for: "title") == "keep me")
        #expect(reread.value(for: "coach_confidence") == "2")
        #expect(reread.editable.recallQuestion == "How does relaxation work?")
        #expect(reread.editable.content == "# Dijkstra\n\n## Key points\n- min-heap")
        #expect(ReviewLog.entries(in: reread).count == 1)
        #expect(reread.section(CoachKey.recallAttemptsHeading) == "- 2026-11-02 · greedy pick")
        #expect(reread.body.hasPrefix("# Dijkstra\n\n## Recall question\nHow does relaxation work?\n\n## Key points"))
    }

    @Test func removingRecallQuestionAndNoTitle() {
        var doc = NoteDocument(text: original)
        doc.applyEditable(EditableNote(recallQuestion: "  ", content: "Just text"))
        #expect(doc.section(CoachKey.recallHeading) == nil)
        #expect(doc.body.hasPrefix("Just text\n\n## Review log"))
        var plain = NoteDocument(text: "---\na: 1\n---\n")
        plain.applyEditable(EditableNote(recallQuestion: "Q?", content: ""))
        #expect(plain.body == "## Recall question\nQ?\n")
    }

    @Test func savingUnchangedIsStable() {
        var doc = NoteDocument(text: original)
        doc.applyEditable(doc.editable)
        let once = doc.render()
        doc.applyEditable(doc.editable)
        #expect(doc.render() == once)
        #expect(EditableNote(recallQuestion: "a\n", content: " b").isSame(as: EditableNote(recallQuestion: "a", content: "b")))
    }
}

@Suite struct MarkdownEditingTests {
    func apply(_ e: TextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }
    func caret(_ text: String) -> Int { (text as NSString).length }

    @Test func returnContinuesAndEndsLists() {
        var t = "- milk"
        var e = MarkdownEditing.newline(in: t, at: caret(t))!
        #expect(apply(e, to: t) == "- milk\n- ")
        t = "\t3. three"
        e = MarkdownEditing.newline(in: t, at: caret(t))!
        #expect(apply(e, to: t) == "\t3. three\n\t4. ")
        t = "- [x] done"
        e = MarkdownEditing.newline(in: t, at: caret(t))!
        #expect(apply(e, to: t) == "- [x] done\n- [ ] ")
        t = "a\n- "
        e = MarkdownEditing.newline(in: t, at: caret(t))!
        #expect(apply(e, to: t) == "a\n")
        t = "\t- "
        e = MarkdownEditing.newline(in: t, at: caret(t))!
        #expect(apply(e, to: t) == "- ")
        #expect(MarkdownEditing.newline(in: "plain", at: 5) == nil)
        #expect(MarkdownEditing.newline(in: "- item", at: 1) == nil)
    }

    @Test func tabIndentsListItems() {
        let t = "- a\n- b"
        let e = MarkdownEditing.indent(in: t, selection: NSRange(location: 0, length: 7), outdent: false)!
        #expect(apply(e, to: t) == "\t- a\n\t- b")
        let back = MarkdownEditing.indent(in: "\t- a", selection: NSRange(location: 4, length: 0), outdent: true)!
        #expect(apply(back, to: "\t- a") == "- a")
        #expect(MarkdownEditing.indent(in: "text", selection: NSRange(location: 0, length: 0), outdent: false) == nil)
    }

    @Test func wrapsAndUnwraps() {
        let t = "make this bold"
        let e = MarkdownEditing.toggleWrap("**", in: t, selection: NSRange(location: 10, length: 4))
        let bold = apply(e, to: t)
        #expect(bold == "make this **bold**")
        #expect(e.selection == NSRange(location: 12, length: 4))
        let off = MarkdownEditing.toggleWrap("**", in: bold, selection: e.selection)
        #expect(apply(off, to: bold) == t)
        // Italic inside bold is added, not mistaken for an existing italic.
        let italic = MarkdownEditing.toggleWrap("*", in: bold, selection: e.selection)
        #expect(apply(italic, to: bold) == "make this ***bold***")
        let empty = MarkdownEditing.toggleWrap("`", in: "x", selection: NSRange(location: 1, length: 0))
        #expect(apply(empty, to: "x") == "x``" && empty.selection.location == 2)
    }

    @Test func headingsAndLineStyles() {
        let t = "Title"
        let h2 = apply(MarkdownEditing.setHeading(2, in: t, selection: NSRange(location: 2, length: 0)), to: t)
        #expect(h2 == "## Title")
        #expect(apply(MarkdownEditing.setHeading(2, in: h2, selection: NSRange(location: 4, length: 0)), to: h2) == "Title")
        #expect(apply(MarkdownEditing.setHeading(1, in: h2, selection: NSRange(location: 4, length: 0)), to: h2) == "# Title")

        let lines = "a\n\nb"
        let all = NSRange(location: 0, length: 4)
        let numbered = apply(MarkdownEditing.toggleLineStyle(.numbered, in: lines, selection: all), to: lines)
        #expect(numbered == "1. a\n\n2. b")
        let bullets = apply(MarkdownEditing.toggleLineStyle(.bullet, in: numbered, selection: NSRange(location: 0, length: 10)), to: numbered)
        #expect(bullets == "- a\n\n- b")
        #expect(apply(MarkdownEditing.toggleLineStyle(.bullet, in: bullets, selection: NSRange(location: 0, length: 8)), to: bullets) == lines)

        let task = apply(MarkdownEditing.toggleLineStyle(.task, in: "- buy", selection: NSRange(location: 0, length: 0)), to: "- buy")
        #expect(task == "- [ ] buy")
        #expect(apply(MarkdownEditing.toggleLineStyle(.task, in: task, selection: NSRange(location: 0, length: 0)), to: task) == "- [x] buy")
    }

    @Test func insertsBlocksOnTheirOwnLines() {
        let t = "intro"
        let e = MarkdownEditing.codeBlock(in: t, selection: NSRange(location: 5, length: 0))
        #expect(apply(e, to: t) == "intro\n\n```\n\n```\n")
        #expect(e.selection.location == 11)
        let l = MarkdownEditing.link(in: "see docs", selection: NSRange(location: 4, length: 4))
        #expect(apply(l, to: "see docs") == "see [docs]()" && l.selection.location == 11)
    }
}

@Suite struct CodeEditingTests {
    func apply(_ e: TextEdit, to t: String) -> String { (t as NSString).replacingCharacters(in: e.range, with: e.replacement) }

    @Test func returnInsideCodeKeepsAndAddsIndent() {
        let t = "```swift\nfunc a() {\n```"
        let caret = ("```swift\nfunc a() {" as NSString).length
        let e = MarkdownEditing.newline(in: t, at: caret)!
        #expect(apply(e, to: t) == "```swift\nfunc a() {\n    \n```")
        // No list continuation inside code.
        let list = "```\n- x\n```"
        let e2 = MarkdownEditing.newline(in: list, at: 7)!
        #expect(apply(e2, to: list) == "```\n- x\n\n```")
    }

    @Test func returnBetweenBracketsSplitsThem() {
        let t = "```\n  if x {}\n```"
        let caret = ("```\n  if x {" as NSString).length
        let e = MarkdownEditing.newline(in: t, at: caret)!
        #expect(apply(e, to: t) == "```\n  if x {\n      \n  }\n```")
        #expect(e.selection.location == caret + 7)
    }

    @Test func returnOnOpeningFenceCloses() {
        let t = "notes\n```python"
        let e = MarkdownEditing.newline(in: t, at: (t as NSString).length)!
        #expect(apply(e, to: t) == "notes\n```python\n\n```")
        #expect(e.selection.location == (t as NSString).length + 1)
        // Already closed: nothing special.
        #expect(MarkdownEditing.newline(in: "```py\n```", at: 5) == nil)
    }

    @Test func tabInCodeInsertsSpaces() {
        let t = "```\nx\n```"
        let e = MarkdownEditing.indent(in: t, selection: NSRange(location: 4, length: 0), outdent: false)!
        #expect(apply(e, to: t) == "```\n    x\n```")
        let back = MarkdownEditing.indent(in: "```\n      x\n```", selection: NSRange(location: 8, length: 0), outdent: true)!
        #expect(apply(back, to: "```\n      x\n```") == "```\n  x\n```")
    }

    @Test func codeBlockWithLanguage() {
        let e = MarkdownEditing.codeBlock(in: "", selection: NSRange(location: 0, length: 0), language: "python")
        #expect(apply(e, to: "") == "```python\n\n```\n" && e.selection.location == 10)
    }
}

@Suite struct CodeSyntaxTests {
    func kinds(_ code: String, _ lang: String?) -> [(String, CodeTokenKind)] {
        CodeSyntax.tokens(code, language: lang).map { ((code as NSString).substring(with: $0.range), $0.kind) }
    }

    @Test func swift() {
        let k = kinds("let x = foo(42) // hi\nlet s: String = \"a\\\"b\"", "swift")
        #expect(k.contains { $0 == ("let", .keyword) })
        #expect(k.contains { $0 == ("foo", .function) })
        #expect(k.contains { $0 == ("42", .number) })
        #expect(k.contains { $0 == ("// hi", .comment) })
        #expect(k.contains { $0 == ("String", .type) })
        #expect(k.contains { $0 == ("\"a\\\"b\"", .string) })
    }

    @Test func python() {
        let k = kinds("def f(n):\n    \"\"\"doc\nmore\"\"\"\n    return None  # done\n@cache", "py")
        #expect(k.contains { $0 == ("def", .keyword) })
        #expect(k.contains { $0 == ("\"\"\"doc\nmore\"\"\"", .string) })
        #expect(k.contains { $0 == ("None", .constant) })
        #expect(k.contains { $0 == ("# done", .comment) })
        #expect(k.contains { $0 == ("@cache", .attribute) })
    }

    @Test func otherLanguages() {
        #expect(kinds("SELECT id FROM t -- x", "sql").contains { $0 == ("SELECT", .keyword) && true })
        #expect(kinds("#include <stdio.h>\nint main()", "c").contains { $0 == ("#include <stdio.h>", .attribute) })
        #expect(kinds("<div class=\"a\">", "html").contains { $0 == ("div", .tag) })
        #expect(kinds("name: coach", "yaml").contains { $0 == ("name", .attribute) })
        #expect(kinds("x = 0x1F + 1e-9", nil).filter { $0.1 == .number }.map(\.0) == ["0x1F", "1e-9"])
        #expect(CodeSyntax.fenceLanguage("```python {1}") == "python")
        #expect(CodeSyntax.fenceLanguage("```") == nil)
    }
}

@Suite struct DailyPlanTests {
    let cal = Calendar.current
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 10))!

    func topic(_ id: String, dueIn days: Int, gap: Int, confidence: Int = 3, reviewedToday: Bool = false) -> Topic {
        let today = cal.startOfDay(for: now)
        var t = Topic(document: NoteDocument(text: "---\ncoach_id: \(id)\n---\n"), url: URL(fileURLWithPath: "/v/\(id).md"))!
        t.confidence = confidence
        t.nextReview = cal.date(byAdding: .day, value: days, to: today)!
        t.lastReviewed = reviewedToday ? now : cal.date(byAdding: .day, value: days - gap, to: today)!
        return t
    }

    @Test func topsUpWithNearlyDueFiles() {
        let topics = [topic("due", dueIn: 0, gap: 4), topic("soon", dueIn: 1, gap: 10), topic("later", dueIn: 8, gap: 10),
                      topic("far", dueIn: 40, gap: 45)]
        let plan = DailyPlan(topics: topics, goal: 3, now: now)
        #expect(plan.due.map(\.id) == ["due"])
        #expect(plan.ahead.map(\.id) == ["soon", "later"])
        #expect(plan.moreDue.isEmpty)
    }

    @Test func capsABacklogByPriority() {
        // Overdue 3 days on a 2-day gap beats overdue 3 days on a 60-day gap.
        let topics = [topic("long", dueIn: -3, gap: 60), topic("short", dueIn: -3, gap: 2), topic("today", dueIn: 0, gap: 5)]
        let plan = DailyPlan(topics: topics, goal: 2, now: now)
        #expect(plan.due.map(\.id) == ["short", "long"])
        #expect(plan.moreDue.map(\.id) == ["today"])
        #expect(plan.ahead.isEmpty)
    }

    @Test func reviewsTodayCountTowardTheGoal() {
        let topics = [topic("done1", dueIn: 5, gap: 5, reviewedToday: true), topic("done2", dueIn: 5, gap: 5, reviewedToday: true),
                      topic("soon", dueIn: 1, gap: 5)]
        let plan = DailyPlan(topics: topics, goal: 2, now: now)
        #expect(plan.isGoalMet && plan.today.isEmpty)
        #expect(DailyPlan(topics: topics, goal: 3, now: now).ahead.map(\.id) == ["soon"])
    }

    @Test func earlyReviewsGrowTheGapLess() {
        let onTime = Scheduler.afterReview(confidence: 4, previousStreak: 2, reviewedAt: now, progress: 1)
        let early = Scheduler.afterReview(confidence: 4, previousStreak: 2, reviewedAt: now, progress: 0.2)
        let days = { (r: Scheduler.Result) in cal.dateComponents([.day], from: cal.startOfDay(for: now), to: r.nextReview).day! }
        #expect(days(onTime) == 18 && onTime.streak == 3)
        #expect(days(early) == 11 && early.streak == 2)
        // A weak rating counts in full even when early.
        #expect(Scheduler.afterReview(confidence: 1, previousStreak: 4, reviewedAt: now, progress: 0.2).streak == 0)
    }
}
