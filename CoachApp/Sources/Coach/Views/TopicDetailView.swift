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
                    HStack {
                        Text("Note").font(.headline)
                        Spacer()
                        Button { editNote() } label: { Label("Edit", systemImage: "square.and.pencil") }
                            .controlSize(.small)
                    }
                    let text = note?.body(removingSections: [CoachKey.recallHeading, CoachKey.reviewLogHeading,
                                                             CoachKey.recallAttemptsHeading], title: topic.title) ?? ""
                    if text.isEmpty {
                        EmptyNotePrompt(action: editNote)
                    } else {
                        MarkdownView(markdown: text, noteURL: topic.url)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gardenCard(radius: 8)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .task(id: "\(topic.url.path)|\(store.scanGeneration)|\(topic.reviewCount)|\(topic.confidence)|\(topic.nextReview)") {
            note = store.noteBody(for: topic.url)
            rating = topic.confidence
        }
        .confirmationDialog("Uproot “\(topic.title)”?", isPresented: $confirmUntrack) {
            Button("Uproot (Stop Tracking)", role: .destructive) { store.untrack(topic) }
        } message: {
            Text("The note stays in your vault. Only Coach's properties are removed.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title).font(.largeTitle.bold()).textSelection(.enabled)
                HStack(spacing: 8) {
                    Label(topic.folderDisplay, systemImage: "leaf").foregroundStyle(.secondary)
                    ConfidenceBadge(confidence: topic.confidence)
                }
            }
            Spacer()
            HStack {
                Button { openWindow.revise(topic.id) } label: { Label("Water Now", systemImage: "drop.fill") }
                    .buttonStyle(.borderedProminent)
                    .help("Open a dedicated revision page for this topic (⌘O, or double-click it in the list)")
                Button(action: editNote) { Label("Edit Note", systemImage: "square.and.pencil") }
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Write the recall question and notes for this file (⌘E)")
                Button { store.openInObsidian(topic.url) } label: { Label("Open in Obsidian", systemImage: "arrow.up.forward.app") }
                Menu {
                    TopicMenu(topic: topic)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func editNote() { openWindow.editNote(topic.id) }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
            GridRow {
                fact("Planted", topic.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                fact("Last watered", topic.lastReviewed.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                fact("Next watering", topic.nextReview.formatted(date: .abbreviated, time: .omitted))
            }
            GridRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status").font(.caption).foregroundStyle(.secondary)
                    DueLabel(topic: topic, now: store.now)
                }
                fact("Waterings", "\(topic.reviewCount)")
                fact("Growth streak", topic.streak > 0 ? "\(topic.streak) in a row 🌿" : "—")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gardenCard(radius: 10)
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private var reviewBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Watered it just now? How well is it growing?").font(.headline)
            ConfidencePicker(selection: $rating)
            HStack {
                Button("Log Watering") { store.review(topic, confidence: rating) }
                    .buttonStyle(.borderedProminent)
                Text("Next watering \(Scheduler.afterReview(of: topic, confidence: rating).nextReview.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Only Change Stage") { store.setConfidence(topic, to: rating) }
                    .disabled(rating == topic.confidence)
                    .help("Change the growth stage (confidence or importance) without logging a watering")
            }
        }
    }
}
