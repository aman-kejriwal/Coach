import CoachCore
import SwiftUI

struct AddTopicView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var subject = ""
    @State private var confidence = 3
    @State private var hasRevised = false
    @State private var lastRevised = Date()
    @State private var question = ""
    @State private var notes = ""
    @FocusState private var titleFocused: Bool

    private var nextReview: Date {
        hasRevised
            ? Scheduler.afterReview(confidence: confidence, previousStreak: 0, reviewedAt: lastRevised).nextReview
            : Scheduler.firstReview(confidence: confidence, addedAt: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Topic", text: $title, prompt: Text("e.g. Dijkstra's algorithm"))
                        .focused($titleFocused)
                    HStack {
                        TextField("Subject", text: $subject, prompt: Text("e.g. DSA"))
                        if !store.subjects.isEmpty {
                            Menu {
                                ForEach(store.subjects, id: \.self) { s in Button(s) { subject = s } }
                            } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }
                Section("Confidence") {
                    ConfidencePicker(selection: $confidence)
                    Text("Low means shaky, or too important to forget. Either way it comes back more often.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Revision") {
                    LastRevisedField(hasRevised: $hasRevised, date: $lastRevised)
                    LabeledContent("First review", value: nextReview.formatted(date: .complete, time: .omitted))
                }
                Section("Optional") {
                    TextField("Recall question", text: $question, prompt: Text("A question to test yourself with"), axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Notes", text: $notes, prompt: Text("Key points (Markdown)"), axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("Saved to \(store.coachFolderName)/\(subject.isEmpty ? "General" : subject)/")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Topic") {
                    if let t = store.createTopic(title: title, subject: subject, confidence: confidence,
                                                 recallQuestion: question, notes: notes,
                                                 lastRevised: hasRevised ? lastRevised : nil) {
                        store.selectedTopicID = t.id
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
        .onAppear { titleFocused = true }
    }
}

/// Detail pane for a note that isn't tracked yet.
struct TrackNoteView: View {
    @Environment(VaultStore.self) private var store
    let url: URL
    let onTracked: (String) -> Void

    @State private var subject = ""
    @State private var confidence = 3
    @State private var hasRevised = false
    @State private var lastRevised = Date()
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(url.deletingPathExtension().lastPathComponent).font(.largeTitle.bold())
                Text(store.relativePath(url)).font(.caption).foregroundStyle(.secondary)
            }
            Form {
                TextField("Subject", text: $subject)
                LabeledContent("Confidence") { ConfidencePicker(selection: $confidence) }
                LastRevisedField(hasRevised: $hasRevised, date: $lastRevised)
            }
            .formStyle(.grouped)
            .frame(maxHeight: 260)
            HStack {
                Button("Start Tracking") {
                    if let id = store.track(url, subject: subject, confidence: confidence,
                                            lastRevised: hasRevised ? lastRevised : nil) {
                        onTracked(id)
                    }
                }
                .buttonStyle(.borderedProminent)
                Text("Adds coach_* properties to this note. Nothing else changes.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open in Obsidian") { store.openInObsidian(url) }
            }
            NotePreview(text: text)
        }
        .padding(24)
        .task {
            subject = url.deletingLastPathComponent().lastPathComponent
            if url.deletingLastPathComponent().standardizedFileURL == store.vaultURL?.standardizedFileURL { subject = "General" }
            text = store.noteBody(for: url)?.body ?? ""
        }
    }
}
