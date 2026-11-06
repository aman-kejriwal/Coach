import AppKit
import CoachCore
import Observation
import SwiftUI

enum PresentedSheet: Identifiable {
    case addTopic
    case review
    var id: String { "\(self)" }
}

struct UndoRecord {
    let url: URL
    let originalText: String
    let label: String
}

/// Single source of app state. The vault on disk is the source of truth; `topics` is a cache rebuilt by scanning.
@MainActor @Observable
final class VaultStore {
    private(set) var vaultURL: URL?
    private(set) var topics: [Topic] = []
    private(set) var untrackedNotes: [URL] = []
    private(set) var isScanning = false
    private(set) var lastUndo: UndoRecord?
    /// Bumped every few minutes and at midnight so "due" counts stay correct while the app sits open.
    private(set) var now = Date()
    /// Increments after every vault scan, so open pages reload note text edited in Obsidian.
    private(set) var scanGeneration = 0
    var errorMessage: String?
    var presentedSheet: PresentedSheet?
    var selectedTopicID: String?

    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var pendingScan: Task<Void, Never>?
    @ObservationIgnored private var clock: Timer?

    static let vaultPathKey = "vaultPath"
    static let coachFolderKey = "coachFolderName"
    static let lastSubjectKey = "lastSubject"

    var coachFolderName: String {
        let v = UserDefaults.standard.string(forKey: Self.coachFolderKey) ?? ""
        return v.isEmpty ? "Coach" : v
    }

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.vaultPathKey) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { open(url) }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.afterChange()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.scheduleScan()
            }
        }
    }

    // MARK: Derived

    var dueTopics: [Topic] { topics.filter { $0.isDue(now: now) }.sorted(by: Topic.urgency) }
    var dueCount: Int { topics.reduce(0) { $0 + ($1.isDue(now: now) ? 1 : 0) } }
    var subjects: [String] { Array(Set(topics.map(\.subjectName))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    func topic(id: String?) -> Topic? { id.flatMap { id in topics.first { $0.id == id } } }

    func relativePath(_ url: URL) -> String {
        guard let root = vaultURL?.standardizedFileURL.path else { return url.path }
        let p = url.standardizedFileURL.path
        return p.hasPrefix(root + "/") ? String(p.dropFirst(root.count + 1)) : p
    }

    // MARK: Vault

    func open(_ url: URL) {
        vaultURL = url
        UserDefaults.standard.set(url.path, forKey: Self.vaultPathKey)
        watcher = VaultWatcher(url: url) { [weak self] in self?.scheduleScan() }
        topics = []
        untrackedNotes = []
        scanNow()
    }

    func closeVault() {
        watcher = nil
        vaultURL = nil
        topics = []
        untrackedNotes = []
        UserDefaults.standard.removeObject(forKey: Self.vaultPathKey)
        afterChange()
    }

    /// Debounced: bursts of file events (Obsidian autosave, our own writes) become one scan.
    func scheduleScan() {
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.scan()
        }
    }

    func scanNow() {
        pendingScan?.cancel()
        pendingScan = Task { [weak self] in await self?.scan() }
    }

    private func scan() async {
        guard let root = vaultURL else { return }
        isScanning = true
        let result = await Task.detached(priority: .userInitiated) { VaultScanner.scan(root: root) }.value
        isScanning = false
        guard root == vaultURL else { return }

        if !result.duplicateIDs.isEmpty {
            // A copied note carries the original's id; give each copy its own identity and history.
            for url in result.duplicateIDs {
                _ = try? rewrite(url) { $0.set(CoachKey.id, UUID().uuidString) }
            }
            scheduleScan()
        }
        topics = result.topics
        untrackedNotes = result.untracked
        scanGeneration += 1
        afterChange()
    }

    private func afterChange() {
        let due = vaultURL == nil ? 0 : dueCount
        NSApp?.dockTile.badgeLabel = due > 0 ? "\(due)" : nil
        Notifier.shared.reschedule(topics: topics)
    }

    // MARK: Writing

    /// Reads the note fresh, applies the change, writes atomically. Returns the updated document.
    @discardableResult
    private func rewrite(_ url: URL, undoLabel: String? = nil, _ change: (inout NoteDocument) -> Void) throws -> NoteDocument {
        let original = try String(contentsOf: url, encoding: .utf8)
        var doc = NoteDocument(text: original)
        change(&doc)
        try doc.render().write(to: url, atomically: true, encoding: .utf8)
        if let undoLabel { lastUndo = UndoRecord(url: url, originalText: original, label: undoLabel) }
        return doc
    }

    /// The note may have been renamed or moved in Obsidian since the last scan; find it again by id.
    private func currentURL(for topic: Topic) -> URL? {
        if FileManager.default.fileExists(atPath: topic.url.path) { return topic.url }
        guard let root = vaultURL else { return nil }
        return VaultScanner.scan(root: root).topics.first { $0.id == topic.id }?.url
    }

    private func mutate(_ topic: Topic, undoLabel: String?, _ change: (inout NoteDocument) -> Void) {
        guard let url = currentURL(for: topic) else {
            errorMessage = "Couldn't find “\(topic.title)” in the vault. It may have been deleted."
            scanNow()
            return
        }
        do {
            let doc = try rewrite(url, undoLabel: undoLabel, change)
            if let updated = Topic(document: doc, url: url), let i = topics.firstIndex(where: { $0.id == topic.id }) {
                topics[i] = updated
            } else {
                scheduleScan()
            }
            afterChange()
        } catch {
            errorMessage = "Couldn't save “\(topic.title)”: \(error.localizedDescription)"
        }
    }

    private static func log(_ text: String, at date: Date = Date()) -> String {
        "- \(CoachDates.logStamp(date)) · \(text)"
    }

    /// Writes all Coach keys for a newly added or newly tracked topic.
    private func applyNewTopicKeys(
        to doc: inout NoteDocument, subject: String, confidence: Int, lastRevised: Date?, now: Date, logText: String
    ) {
        let next: Date
        var streak = 0
        if let lastRevised {
            let r = Scheduler.afterReview(confidence: confidence, previousStreak: 0, reviewedAt: lastRevised)
            next = r.nextReview
            streak = r.streak
        } else {
            next = Scheduler.firstReview(confidence: confidence, addedAt: now)
        }
        doc.set(CoachKey.id, UUID().uuidString)
        doc.set(CoachKey.subject, subject, quoted: true)
        doc.set(CoachKey.confidence, "\(confidence)")
        doc.set(CoachKey.created, CoachDates.dateTime(now))
        doc.set(CoachKey.lastReviewed, lastRevised.map(CoachDates.dateTime))
        doc.set(CoachKey.nextReview, CoachDates.day(next))
        doc.set(CoachKey.reviewCount, lastRevised == nil ? "0" : "1")
        doc.set(CoachKey.streak, "\(streak)")
        doc.set(CoachKey.schema, "\(CoachKey.currentSchema)")
        doc.appendLine(Self.log(logText, at: now), toSection: CoachKey.reviewLogHeading)
        if let lastRevised {
            doc.appendLine(Self.log("last revised \(CoachDates.logStamp(lastRevised)), next review \(CoachDates.day(next))", at: now),
                           toSection: CoachKey.reviewLogHeading)
        }
    }

    // MARK: Actions

    @discardableResult
    func createTopic(title: String, subject: String, confidence: Int, recallQuestion: String,
                     notes: String, lastRevised: Date?) -> Topic? {
        guard let root = vaultURL else { return nil }
        let name = VaultScanner.sanitizeFileName(title)
        guard !name.isEmpty else { errorMessage = "Please enter a topic name."; return nil }
        let subjectName = subject.trimmingCharacters(in: .whitespaces).isEmpty ? "General" : subject.trimmingCharacters(in: .whitespaces)
        let folder = root.appendingPathComponent(coachFolderName, isDirectory: true)
            .appendingPathComponent(VaultScanner.sanitizeFileName(subjectName), isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent(name + ".md")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(name) \(n).md")
                n += 1
            }

            var body = "# \(title.trimmingCharacters(in: .whitespaces))\n"
            let q = recallQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { body += "\n\(CoachKey.recallHeading)\n\(q)\n" }
            body += "\n## Notes\n\(notes.trimmingCharacters(in: .whitespacesAndNewlines))\n"

            var doc = NoteDocument(text: body)
            let now = Date()
            applyNewTopicKeys(to: &doc, subject: subjectName, confidence: confidence, lastRevised: lastRevised,
                              now: now, logText: "added (confidence \(confidence))")
            doc.addListIfMissing("tags", items: ["coach"])
            try doc.render().write(to: url, atomically: true, encoding: .utf8)

            UserDefaults.standard.set(subjectName, forKey: Self.lastSubjectKey)
            let topic = Topic(document: doc, url: url)
            if let topic { topics.append(topic) }
            afterChange()
            return topic
        } catch {
            errorMessage = "Couldn't create the note: \(error.localizedDescription)"
            return nil
        }
    }

    /// Starts tracking a note that already exists in the vault. Only Coach's own keys are added.
    @discardableResult
    func track(_ url: URL, subject: String, confidence: Int, lastRevised: Date?) -> String? {
        do {
            var newID: String?
            let doc = try rewrite(url, undoLabel: "Track “\(url.deletingPathExtension().lastPathComponent)”") { doc in
                guard doc.value(for: CoachKey.id) == nil else { return }
                applyNewTopicKeys(to: &doc, subject: subject.isEmpty ? "General" : subject, confidence: confidence,
                                  lastRevised: lastRevised, now: Date(), logText: "added to Coach (confidence \(confidence))")
            }
            if let topic = Topic(document: doc, url: url) {
                newID = topic.id
                if !topics.contains(where: { $0.id == topic.id }) { topics.append(topic) }
                untrackedNotes.removeAll { $0 == url }
            }
            afterChange()
            return newID
        } catch {
            errorMessage = "Couldn't update the note: \(error.localizedDescription)"
            return nil
        }
    }

    /// Records a revision. `confidence` is how well you know it right now.
    /// `duration` (time spent) goes into the log; `recall` (what you wrote from memory) is saved under `## Recall attempts`.
    func review(_ topic: Topic, confidence: Int, duration: TimeInterval? = nil, recall: String? = nil) {
        let now = Date()
        let minutes = duration.map { max(1, Int(($0 / 60).rounded())) }
        let recallText = recall?.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = Scheduler.afterReview(confidence: confidence, previousStreak: topic.streak, reviewedAt: now)
        mutate(topic, undoLabel: "Review of “\(topic.title)”") { doc in
            doc.set(CoachKey.confidence, "\(confidence)")
            doc.set(CoachKey.lastReviewed, CoachDates.dateTime(now))
            doc.set(CoachKey.nextReview, CoachDates.day(r.nextReview))
            doc.set(CoachKey.reviewCount, "\(topic.reviewCount + 1)")
            doc.set(CoachKey.streak, "\(r.streak)")
            let spent = minutes.map { " · \($0) min" } ?? ""
            doc.appendLine(Self.log("reviewed · confidence \(confidence)\(spent) · next \(CoachDates.day(r.nextReview))", at: now),
                           toSection: CoachKey.reviewLogHeading)
            if let recallText, !recallText.isEmpty {
                let lines = recallText.components(separatedBy: "\n")
                let entry = (["- \(CoachDates.logStamp(now)) · " + lines[0]] + lines.dropFirst().map { "  " + $0 })
                    .joined(separator: "\n")
                doc.appendLine(entry, toSection: CoachKey.recallAttemptsHeading)
            }
        }
    }

    /// Changes confidence without logging a review. Lowering it pulls the next review closer if needed.
    func setConfidence(_ topic: Topic, to confidence: Int) {
        guard confidence != topic.confidence else { return }
        let sooner = Scheduler.firstReview(confidence: confidence, addedAt: Date())
        let next = min(topic.nextReview, sooner)
        mutate(topic, undoLabel: "Confidence change") { doc in
            doc.set(CoachKey.confidence, "\(confidence)")
            doc.set(CoachKey.nextReview, CoachDates.day(next))
            doc.appendLine(Self.log("confidence \(topic.confidence) → \(confidence)"), toSection: CoachKey.reviewLogHeading)
        }
    }

    func postpone(_ topic: Topic, days: Int) {
        let base = max(Calendar.current.startOfDay(for: Date()), topic.nextReview)
        let next = Calendar.current.date(byAdding: .day, value: days, to: base)!
        mutate(topic, undoLabel: "Postpone") { doc in
            doc.set(CoachKey.nextReview, CoachDates.day(next))
            doc.appendLine(Self.log("postponed to \(CoachDates.day(next))"), toSection: CoachKey.reviewLogHeading)
        }
    }

    /// Removes Coach's keys from the note. The note itself and its review log stay in the vault.
    func untrack(_ topic: Topic) {
        mutate(topic, undoLabel: "Stop tracking “\(topic.title)”") { doc in
            for key in CoachKey.all { doc.set(key, nil) }
        }
        topics.removeAll { $0.id == topic.id }
        if selectedTopicID == topic.id { selectedTopicID = nil }
        scheduleScan()
    }

    func undo() {
        guard let u = lastUndo else { return }
        do {
            try u.originalText.write(to: u.url, atomically: true, encoding: .utf8)
            lastUndo = nil
            scanNow()
        } catch {
            errorMessage = "Couldn't undo: \(error.localizedDescription)"
        }
    }

    func noteBody(for url: URL) -> NoteDocument? {
        (try? String(contentsOf: url, encoding: .utf8)).map(NoteDocument.init(text:))
    }

    // MARK: Opening

    func openInObsidian(_ url: URL) {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        if let encoded = url.path.addingPercentEncoding(withAllowedCharacters: allowed),
           let link = URL(string: "obsidian://open?path=\(encoded)"),
           NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
            NSWorkspace.shared.open(link)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
