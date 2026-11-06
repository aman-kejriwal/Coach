import CoachCore
import SwiftUI

struct TopicDetailView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let topic: Topic
    @State private var note: NoteDocument?
    @State private var rating = 3
    @State private var confirmUntrack = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                facts
                reviewBox
                if let q = note?.section(CoachKey.recallHeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recall question").font(.headline)
                        Text(q).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Note").font(.headline)
                    MarkdownView(markdown: note?.body(removingSections: [CoachKey.recallHeading], title: topic.title) ?? "")
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .task(id: "\(topic.url.path)|\(store.scanGeneration)|\(topic.reviewCount)|\(topic.confidence)|\(topic.nextReview)") {
            note = store.noteBody(for: topic.url)
            rating = topic.confidence
        }
        .confirmationDialog("Stop tracking “\(topic.title)”?", isPresented: $confirmUntrack) {
            Button("Stop Tracking", role: .destructive) { store.untrack(topic) }
        } message: {
            Text("The note stays in your vault. Only Coach's properties are removed.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title).font(.largeTitle.bold()).textSelection(.enabled)
                HStack(spacing: 8) {
                    Label(topic.subjectName, systemImage: "folder").foregroundStyle(.secondary)
                    ConfidenceBadge(confidence: topic.confidence)
                }
            }
            Spacer()
            HStack {
                Button { openWindow.revise(topic.id) } label: { Label("Revise Now", systemImage: "rectangle.portrait.and.arrow.forward") }
                    .buttonStyle(.borderedProminent)
                    .help("Open a dedicated revision page for this topic (⌘O, or double-click it in the list)")
                Button { store.openInObsidian(topic.url) } label: { Label("Open in Obsidian", systemImage: "arrow.up.forward.app") }
                Menu {
                    TopicMenu(topic: topic)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
            GridRow {
                fact("Added", topic.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                fact("Last revised", topic.lastReviewed.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                fact("Next review", topic.nextReview.formatted(date: .abbreviated, time: .omitted))
            }
            GridRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status").font(.caption).foregroundStyle(.secondary)
                    DueLabel(topic: topic, now: store.now)
                }
                fact("Reviews", "\(topic.reviewCount)")
                fact("Streak", topic.streak > 0 ? "\(topic.streak) in a row" : "—")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private var reviewBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Revised it just now? How confident are you?").font(.headline)
            ConfidencePicker(selection: $rating)
            HStack {
                Button("Log Review") { store.review(topic, confidence: rating) }
                    .buttonStyle(.borderedProminent)
                Text("Next review in \(Scheduler.intervalDays(confidence: rating, streak: rating <= 2 ? 0 : topic.streak)) days")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Only Change Confidence") { store.setConfidence(topic, to: rating) }
                    .disabled(rating == topic.confidence)
                    .help("Update confidence (or importance) without logging a revision")
            }
        }
    }
}
