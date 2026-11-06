import Charts
import CoachCore
import SwiftUI

extension OpenWindowAction {
    /// Opens (or brings forward) the dedicated revision window for a topic.
    @MainActor func revise(_ topicID: String) {
        self(id: "revise", value: topicID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Root of a "Revise" window. The bound id can change in place ("Next due topic").
struct RevisePage: View {
    @Environment(VaultStore.self) private var store
    @Binding var topicID: String?

    var body: some View {
        if let id = topicID, let topic = store.topic(id: id) {
            ReviseContent(topic: topic, topicID: $topicID)
                .id(id) // fresh state (timer, scratchpad, rating) for each topic
                .navigationTitle(topic.title)
                .navigationSubtitle(topic.subjectName)
        } else {
            ContentUnavailableView("Topic not found", systemImage: "questionmark.folder",
                                   description: Text("It may have been deleted or untracked."))
                .navigationTitle("Revise")
        }
    }
}

private struct ReviseContent: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let topic: Topic
    @Binding var topicID: String?

    @State private var startedAt = Date()
    @State private var recall = ""
    @State private var saveRecall = false
    @State private var revealed = false
    @State private var note: NoteDocument?
    @State private var logged: (confidence: Int, next: Date)?

    private var noteText: String {
        note?.body(removingSections: [CoachKey.recallHeading, CoachKey.reviewLogHeading, CoachKey.recallAttemptsHeading],
                   title: topic.title) ?? ""
    }

    /// The next due topic other than this one, most urgent first.
    private var nextDue: Topic? { store.dueTopics.first { $0.id != topic.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let logged { loggedBanner(logged) }
                recallSection
                noteSection
                if logged == nil { rateSection }
                historySection
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                    Label(Self.clock(ctx.date.timeIntervalSince(startedAt)), systemImage: "timer")
                        .monospacedDigit()
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
                .help("Time on this topic")
                Button { store.openInObsidian(topic.url) } label: {
                    Label("Edit in Obsidian", systemImage: "square.and.pencil")
                }
                .help("Open this note in Obsidian. Changes show up here automatically.")
            }
        }
        // Reload when the note changes (our writes or edits in Obsidian).
        .task(id: "\(topic.url.path)|\(store.scanGeneration)|\(topic.reviewCount)|\(topic.confidence)") {
            note = store.noteBody(for: topic.url)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(topic.subjectName.uppercased())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(topic.title).font(.system(size: 34, weight: .bold)).textSelection(.enabled)
            HStack(spacing: 10) {
                ConfidenceBadge(confidence: topic.confidence)
                DueLabel(topic: topic, now: store.now).font(.callout)
                Text("·").foregroundStyle(.tertiary)
                Text(topic.lastReviewed.map { "Last revised \($0.formatted(.relative(presentation: .named)))" } ?? "Never revised")
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("\(topic.reviewCount) review\(topic.reviewCount == 1 ? "" : "s")\(topic.streak > 0 ? " · \(topic.streak) in a row" : "")")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var recallSection: some View {
        card(step: 1, title: "Recall", subtitle: "Before you look, try to explain it from memory.") {
            if let q = note?.section(CoachKey.recallHeading) {
                Text(MarkdownView.inline(q))
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $recall)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 110)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(logged != nil)
                if recall.isEmpty {
                    Text("Write what you remember: key ideas, steps, formulas, examples…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            Toggle("Save what I wrote to the note (under “Recall attempts”)", isOn: $saveRecall)
                .font(.callout)
                .disabled(logged != nil)
        }
    }

    private var noteSection: some View {
        card(step: 2, title: "Check", subtitle: revealed ? "Compare with what you wrote. What did you miss?" : "Reveal the note when you're ready.") {
            if revealed {
                MarkdownView(markdown: noteText)
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                if let attempts = note?.section(CoachKey.recallAttemptsHeading) {
                    DisclosureGroup("Earlier recall attempts") {
                        MarkdownView(markdown: attempts).padding(.top, 6)
                    }
                    .font(.callout)
                }
            } else {
                Button { withAnimation(.easeOut(duration: 0.2)) { revealed = true } } label: {
                    Label("Show Note", systemImage: "eye").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")
            }
        }
    }

    private var rateSection: some View {
        card(step: 3, title: "Rate", subtitle: "How well did you remember it? Low means it comes back sooner.") {
            HStack(spacing: 8) {
                ForEach(Array(Confidence.range), id: \.self) { c in
                    let next = Scheduler.afterReview(confidence: c, previousStreak: topic.streak, reviewedAt: Date()).nextReview
                    Button { rate(c) } label: {
                        VStack(spacing: 3) {
                            Text("\(c)").font(.title2.bold()).monospacedDigit()
                            Text(Confidence.label(c)).font(.caption)
                            Text(Self.relativeDay(next)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Confidence.color(c).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Confidence.color(c).opacity(0.6)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(c)")), modifiers: .command)
                    .help("⌘\(c): \(Confidence.detail(c)) Next review \(next.formatted(date: .complete, time: .omitted)).")
                }
            }
            HStack {
                if !revealed {
                    Text("Tip: reveal the note first so your rating is honest.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Postpone") {
                    Button("1 day") { postpone(1) }
                    Button("3 days") { postpone(3) }
                    Button("1 week") { postpone(7) }
                }
                .fixedSize()
                Button("Close Without Rating") { dismiss() }
            }
        }
    }

    private func loggedBanner(_ l: (confidence: Int, next: Date)) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review logged · confidence \(l.confidence)").font(.headline)
                Text("Next review \(l.next.formatted(date: .complete, time: .omitted)) (\(Self.relativeDay(l.next)))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.lastUndo != nil {
                Button("Undo") {
                    store.undo()
                    logged = nil
                }
            }
            if let next = nextDue {
                Button("Next: \(next.title) →") { topicID = next.id }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var historySection: some View {
        let entries = note.map(ReviewLog.entries) ?? []
        let points = entries.filter { $0.confidence != nil }
        if !entries.isEmpty {
            card(step: nil, title: "History", subtitle: "Confidence over time, from this note's review log.") {
                if points.count >= 2 {
                    Chart(Array(points.enumerated()), id: \.offset) { _, e in
                        LineMark(x: .value("Date", e.date), y: .value("Confidence", e.confidence!))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.secondary)
                        PointMark(x: .value("Date", e.date), y: .value("Confidence", e.confidence!))
                            .foregroundStyle(Confidence.color(e.confidence!))
                            .symbolSize(60)
                    }
                    .chartYScale(domain: 1...5)
                    .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
                    .frame(height: 140)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entries.suffix(8).reversed().enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(e.confidence.map(Confidence.color) ?? .gray).frame(width: 6, height: 6)
                            Text(e.date.formatted(date: .abbreviated, time: .shortened))
                                .monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)
                            Text(e.text)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func card<Content: View>(step: Int?, title: String, subtitle: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let step {
                    Text("\(step)")
                        .font(.caption.bold())
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor.opacity(0.2)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private func rate(_ c: Int) {
        let next = Scheduler.afterReview(confidence: c, previousStreak: topic.streak, reviewedAt: Date()).nextReview
        store.review(topic, confidence: c, duration: Date().timeIntervalSince(startedAt),
                     recall: saveRecall ? recall : nil)
        withAnimation {
            logged = (c, next)
            revealed = true
        }
    }

    private func postpone(_ days: Int) {
        store.postpone(topic, days: days)
        if let next = nextDue { topicID = next.id } else { dismiss() }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func relativeDay(_ d: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }
}
