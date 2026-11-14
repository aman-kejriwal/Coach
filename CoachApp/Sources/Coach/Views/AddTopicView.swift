import CoachCore
import SwiftUI

/// Picks a folder inside Coach/, indented to show the hierarchy.
struct FolderPicker: View {
    @Environment(VaultStore.self) private var store
    let title: String
    @Binding var selection: [String]?
    var allowNone = true

    var body: some View {
        Picker(title, selection: $selection) {
            if allowNone { Text("Choose a folder…").tag(nil as [String]?) }
            ForEach(store.tree.flattened) { node in
                Text(String(repeating: "    ", count: node.path.count) + (node.isRoot ? "\(node.name) (top level)" : node.name))
                    .tag(Optional(node.path))
            }
        }
    }
}

/// Add one file, or several at once, into a folder. Opens empty every time (nothing carried over),
/// except the folder when it was opened from that folder's "Add Files" button.
struct AddTopicView: View {
    enum Mode: String, CaseIterable { case one = "One file", several = "Several files" }

    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage("openEditorAfterAdding") private var openEditor = true

    let initialFolder: [String]?

    @State private var mode = Mode.one
    @State private var folder: [String]?
    @State private var newFolderName = ""
    @State private var showingNewFolder = false

    @State private var title = ""
    @State private var confidence = 3
    @State private var hasRevised = false
    @State private var lastRevised = Date()
    @State private var question = ""
    @State private var batchText = ""
    @FocusState private var titleFocused: Bool

    private var batch: [(title: String, confidence: Int)] { VaultStore.parseBatch(batchText, defaultConfidence: confidence) }

    private var nextReview: Date {
        hasRevised
            ? Scheduler.afterReview(confidence: confidence, previousStreak: 0, reviewedAt: lastRevised).nextReview
            : Scheduler.firstReview(confidence: confidence, addedAt: Date())
    }

    private var canAdd: Bool {
        guard folder != nil else { return false }
        return mode == .one ? !title.trimmingCharacters(in: .whitespaces).isEmpty : !batch.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Form {
                Section("Where") {
                    FolderPicker(title: "Folder", selection: $folder)
                    if showingNewFolder {
                        HStack {
                            TextField("New folder inside \(VaultStore.display(folder ?? [], root: store.coachFolderName))",
                                      text: $newFolderName)
                                .onSubmit(createFolder)
                            Button("Create", action: createFolder)
                                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button("New folder…") { showingNewFolder = true }
                            .buttonStyle(.link)
                    }
                }

                if mode == .one {
                    Section("File") {
                        TextField("Name", text: $title, prompt: Text("e.g. Dijkstra's algorithm"))
                            .focused($titleFocused)
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
                        Toggle("Open the editor to write notes after adding", isOn: $openEditor)
                    }
                } else {
                    Section {
                        TextEditor(text: $batchText)
                            .font(.body.monospaced())
                            .frame(minHeight: 160)
                    } header: {
                        Text("Files, one per line")
                    } footer: {
                        Text("Add “| 1”–“| 5” at the end of a line to give that file its own confidence, e.g. “Dijkstra | 1”.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Default confidence") {
                        ConfidencePicker(selection: $confidence)
                    }
                    if !batch.isEmpty {
                        Section("Will create \(batch.count) file\(batch.count == 1 ? "" : "s")") {
                            ForEach(Array(batch.prefix(12).enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                    Text(item.title)
                                    Spacer()
                                    ConfidenceBadge(confidence: item.confidence, showLabel: false)
                                }
                            }
                            if batch.count > 12 { Text("+ \(batch.count - 12) more").foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text(folder.map { "Saved to \(store.coachFolderName)/\($0.map { $0 + "/" }.joined())" } ?? "Choose a folder to save into")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .one ? "Add File" : "Add \(batch.count) Files", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .padding()
        }
        .frame(width: 540, height: 640)
        .onAppear {
            folder = initialFolder
            titleFocused = true
        }
    }

    private func createFolder() {
        if let path = store.createFolder(named: newFolderName, in: folder ?? []) {
            folder = path
            newFolderName = ""
            showingNewFolder = false
        }
    }

    private func add() {
        guard let folder else { return }
        switch mode {
        case .one:
            if let t = store.createTopic(title: title, folder: folder, confidence: confidence,
                                         recallQuestion: question,
                                         lastRevised: hasRevised ? lastRevised : nil) {
                store.selectedTopicID = t.id
                dismiss()
                if openEditor { openWindow.editNote(t.id) }
            }
        case .several:
            if store.createTopics(batch, folder: folder) > 0 { dismiss() }
        }
    }
}

/// Creates a folder (subject, topic, subtopic…) inside Coach/.
struct NewFolderView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let parent: [String]
    let onCreated: ([String]) -> Void

    @State private var inside: [String]?
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                FolderPicker(title: "Inside", selection: $inside, allowNone: false)
                TextField("Name", text: $name, prompt: Text("e.g. DSA, Graphs, Shortest Paths"))
                    .focused($focused)
                    .onSubmit(create)
                Text("Folders hold files and other folders. They aren't rated themselves; their statistics come from the files inside.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Folder", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 250)
        .onAppear {
            inside = parent
            focused = true
        }
    }

    private func create() {
        if let path = store.createFolder(named: name, in: inside ?? []) {
            onCreated(path)
            dismiss()
        }
    }
}

/// Detail pane for a Markdown file inside Coach/ that isn't tracked yet.
struct TrackNoteView: View {
    @Environment(VaultStore.self) private var store
    let url: URL
    let onTracked: (String) -> Void

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
                LabeledContent("Confidence") { ConfidencePicker(selection: $confidence) }
                LastRevisedField(hasRevised: $hasRevised, date: $lastRevised)
            }
            .formStyle(.grouped)
            .frame(maxHeight: 220)
            HStack {
                Button("Start Tracking") {
                    if let id = store.track(url, confidence: confidence, lastRevised: hasRevised ? lastRevised : nil) {
                        onTracked(id)
                    }
                }
                .buttonStyle(.borderedProminent)
                Text("Adds coach_* properties to this file. Nothing else changes.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open in Obsidian") { store.openInObsidian(url) }
            }
            ScrollView {
                MarkdownView(markdown: NoteDocument(text: text).body).padding(12)
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .task { text = (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }
}
