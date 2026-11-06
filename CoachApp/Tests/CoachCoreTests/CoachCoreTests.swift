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
        coach_subject: "OS"
        coach_confidence: 1
        coach_created: 2026-11-05T14:32:00+05:30
        coach_next_review: 2026-11-07
        coach_review_count: 4
        ---
        """
        let t = try #require(Topic(document: NoteDocument(text: text), url: URL(fileURLWithPath: "/v/Coach/OS/Paging.md")))
        #expect(t.title == "Paging")
        #expect(t.subjectName == "OS")
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

        let r = VaultScanner.scan(root: root)
        #expect(r.topics.count == 1)
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
