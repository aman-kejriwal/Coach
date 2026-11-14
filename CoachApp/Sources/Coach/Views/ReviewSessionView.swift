import CoachCore
import SwiftUI

/// Active recall: see the topic (and its question), try to remember, reveal the note, then rate 1–5.
struct ReviewSessionView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [String] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var reviewed = 0
    @State private var note: NoteDocument?

    private var current: Topic? {
        index < queue.count ? store.topic(id: queue[index]) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(queue.isEmpty ? "Watering round" : "Watering round · \(min(index + 1, queue.count)) of \(queue.count)")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .tint(Garden.water)
                .padding(.horizontal)

            if let topic = current {
                card(topic)
            } else {
                finished
            }
        }
        .frame(width: 620, height: 600)
        .onAppear {
            queue = store.reviewQueue.map(\.id)
            loadNote()
        }
    }

    private func card(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.folderDisplay.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(topic.title).font(.largeTitle.bold())
                HStack {
                    ConfidenceBadge(confidence: topic.confidence)
                    DueLabel(topic: topic, now: store.now).font(.caption)
                    if let last = topic.lastReviewed {
                        Text("· last watered \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let q = note?.section(CoachKey.recallHeading) {
                Text(q).font(.title3).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Garden.leaf.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Try to explain this topic from memory before you open the note.")
                    .foregroundStyle(.secondary)
            }

            if revealed {
                ScrollView {
                    MarkdownView(markdown: note?.body(removingSections: [CoachKey.recallHeading, CoachKey.reviewLogHeading],
                                                      title: topic.title) ?? "", noteURL: topic.url)
                        .padding(12)
                }
                .gardenCard(radius: 8)
            } else {
                Button { revealed = true } label: {
                    Label("Show Note", systemImage: "eye").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How well is it growing now? (press 1–5)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Array(Confidence.range), id: \.self) { c in
                        ConfidenceButton(confidence: c, shortcut: true) { rate(topic, c) }
                    }
                }
                HStack {
                    Button("Skip") { advance() }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Postpone 1 day") { store.postpone(topic, days: 1); advance() }
                    Button("Open in Obsidian") { store.openInObsidian(topic.url) }
                    Spacer()
                    if store.lastUndo != nil, index > 0 {
                        Button("Undo Last") {
                            store.undo()
                            index -= 1
                            reviewed = max(0, reviewed - 1)
                            revealed = false
                            loadNote()
                        }
                    }
                }
                .font(.callout)
            }
        }
        .padding(24)
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(reviewed > 0 ? "🌻" : "🌤️").font(.system(size: 56))
            Text(reviewed > 0 ? "Round complete" : "Nothing is thirsty right now").font(.title.bold())
            if reviewed > 0 {
                Text(store.plan.isGoalMet
                     ? "You watered \(Garden.plants(reviewed)). Today's round is done."
                     : "You watered \(Garden.plants(reviewed)). See you at the next watering.")
                    .foregroundStyle(.secondary)
            }
            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction).padding(.top)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func rate(_ topic: Topic, _ c: Int) {
        store.review(topic, confidence: c)
        reviewed += 1
        advance()
    }

    private func advance() {
        index += 1
        revealed = false
        loadNote()
    }

    private func loadNote() {
        note = current.flatMap { store.noteBody(for: $0.url) }
    }
}
