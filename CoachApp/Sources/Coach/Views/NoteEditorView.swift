import CoachCore
import SwiftUI

extension OpenWindowAction {
    /// Opens (or brings forward) the note editor window for a file.
    @MainActor func editNote(_ topicID: String) {
        self(id: "editor", value: topicID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Root of an editor window.
struct NoteEditorWindow: View {
    @Environment(VaultStore.self) private var store
    @Binding var topicID: String?

    var body: some View {
        if let topicID, let topic = store.topic(id: topicID) {
            NoteEditor(topic: topic)
                .id(topicID)
                .navigationTitle(topic.title)
                .navigationSubtitle(topic.folderDisplay)
        } else {
            ContentUnavailableView("File not found", systemImage: "questionmark.folder",
                                   description: Text("It may have been deleted or untracked."))
                .navigationTitle("Edit Note")
        }
    }
}

/// A Markdown editor for a file's recall question and notes. Saves automatically; coach_* properties,
/// the review log and recall attempts are never touched.
@MainActor
private struct NoteEditor: View {
    enum Status: Equatable { case saved, edited, conflict }

    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let topic: Topic

    @State private var lastSaved = EditableNote()
    @State private var recall = ""
    @State private var content = ""
    @State private var loaded = false
    @State private var status = Status.saved
    @State private var savedAt: Date?
    @State private var saveTask: Task<Void, Never>?
    @State private var controller = MarkdownEditorController()
    @AppStorage("editorShowsPreview") private var showPreview = false

    private var edit: EditableNote { EditableNote(recallQuestion: recall, content: content) }
    private var isDirty: Bool { loaded && !edit.isSame(as: lastSaved) }

    var body: some View {
        VStack(spacing: 0) {
            if status == .conflict { conflictBanner }
            recallField
            Divider()
            FormattingBar(controller: controller)
            Divider()
            if loaded {
                if showPreview {
                    HSplitView {
                        editor.frame(minWidth: 360)
                        preview.frame(minWidth: 300)
                    }
                } else {
                    editor
                }
            } else {
                Spacer()
            }
            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $showPreview) { Label("Preview", systemImage: "sidebar.right") }
                    .help("Show a preview beside the editor")
                Button { openWindow.revise(topic.id) } label: { Label("Revise", systemImage: "rectangle.portrait.and.arrow.forward") }
                    .help("Open the revision page for this file")
                Button { saveNow(); store.openInObsidian(topic.url) } label: {
                    Label("Open in Obsidian", systemImage: "arrow.up.forward.app")
                }
                .help("Saves, then opens the note in Obsidian")
                Button("Save", action: saveNow)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!isDirty)
                    .help("Coach saves automatically as you type; ⌘S saves right away")
            }
        }
        .onAppear(perform: load)
        .onChange(of: recall) { scheduleSave() }
        .onChange(of: content) { scheduleSave() }
        .onChange(of: store.scanGeneration) { checkDisk() }
        .onDisappear {
            saveTask?.cancel()
            if isDirty && status != .conflict { save(overwrite: false) }
        }
    }

    // MARK: Parts

    private var editor: some View {
        MarkdownEditor(text: $content, controller: controller, saveImage: saveImage, lookUpImage: lookUpImage)
    }

    /// Pasted or dropped images become files in the vault, embedded as ![[name]].
    private func saveImage(_ item: PasteboardImages.Item) -> String? {
        guard let attachments = store.attachments else { return nil }
        do {
            return try attachments.save(item.data, ext: item.ext, name: item.name, for: topic.url)
        } catch {
            store.errorMessage = "Couldn't save the image: \(error.localizedDescription)"
            return nil
        }
    }

    private func lookUpImage(_ target: String) -> NSImage? {
        store.attachments?.resolve(target, from: topic.url).flatMap(ImageCache.image(at:))
    }

    private var recallField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label("Recall question", systemImage: "questionmark.bubble")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .help("Shown first on the revision page, so you test yourself before reading the note.")
            TextField("Recall question", text: $recall,
                      prompt: Text("What should you be able to answer without looking?"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...4)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var preview: some View {
        ScrollView {
            let shown = NoteDocument(text: content).body(removingSections: [], title: topic.title)
            Group {
                if shown.isEmpty {
                    Text("The preview appears here.").foregroundStyle(.tertiary)
                } else {
                    MarkdownView(markdown: shown, noteURL: topic.url)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
    }

    private var conflictBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("This note was changed somewhere else (probably Obsidian) while you were editing. Autosave is paused.")
                .font(.callout)
            Spacer()
            Button("Load Their Version", role: .destructive) { load() }
            Button("Keep Mine") { save(overwrite: true) }
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            switch status {
            case .saved:
                Label(savedAt.map { "Saved \($0.formatted(date: .omitted, time: .shortened))" } ?? "Saved",
                      systemImage: "checkmark.circle")
            case .edited:
                Label("Editing…", systemImage: "pencil.circle")
            case .conflict:
                Label("Not saved: changed elsewhere", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text(store.relativePath(topic.url)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("\(wordCount) words").monospacedDigit()
            Text("Confidence and review history are never changed here.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private var wordCount: Int { (recall + " " + content).split { $0.isWhitespace }.count }

    // MARK: Saving

    private func load() {
        saveTask?.cancel()
        let e = store.noteBody(for: topic.url)?.editable ?? EditableNote()
        lastSaved = e
        recall = e.recallQuestion
        content = e.content
        loaded = true
        status = .saved
    }

    private func scheduleSave() {
        guard loaded, status != .conflict else { return }
        guard isDirty else { status = .saved; return }
        status = .edited
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            save(overwrite: false)
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        if isDirty && status != .conflict { save(overwrite: false) }
    }

    private func save(overwrite: Bool) {
        let current = edit
        switch store.saveNote(topic, current, basedOn: lastSaved, overwrite: overwrite) {
        case .saved:
            lastSaved = current
            savedAt = Date()
            status = isDirty ? .edited : .saved
        case .conflict:
            status = .conflict
        case .failed:
            status = .edited
        }
    }

    /// Something rescanned the vault: pick up edits made in Obsidian, or flag a conflict if we have our own.
    private func checkDisk() {
        guard loaded, let onDisk = store.noteBody(for: topic.url)?.editable, !onDisk.isSame(as: lastSaved) else { return }
        if isDirty {
            if !onDisk.isSame(as: edit) { status = .conflict }
        } else {
            load()
        }
    }
}

/// Formatting buttons above the editor. Each one also has a keyboard shortcut (shown in its tooltip).
private struct FormattingBar: View {
    let controller: MarkdownEditorController

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Heading 1  ⌥⌘1") { controller.run { $0.heading(1) } }
                Button("Heading 2  ⌥⌘2") { controller.run { $0.heading(2) } }
                Button("Heading 3  ⌥⌘3") { controller.run { $0.heading(3) } }
                Button("Normal text  ⌥⌘0") { controller.run { $0.heading(0) } }
            } label: {
                Label("Heading", systemImage: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Heading (⌥⌘1–3)")

            separator
            tool("bold", "Bold (⌘B)") { $0.wrap("**") }
            tool("italic", "Italic (⌘I)") { $0.wrap("*") }
            tool("strikethrough", "Strikethrough (⇧⌘X)") { $0.wrap("~~") }
            tool("highlighter", "Highlight (⇧⌘H)") { $0.wrap("==") }
            tool("chevron.left.forwardslash.chevron.right", "Inline code (⌘E)") { $0.wrap("`") }
            separator
            tool("list.bullet", "Bulleted list (⇧⌘8)") { $0.lineStyle(.bullet) }
            tool("list.number", "Numbered list (⇧⌘7)") { $0.lineStyle(.numbered) }
            tool("checklist", "Checklist, again to tick (⇧⌘9)") { $0.lineStyle(.task) }
            tool("text.quote", "Quote (⇧⌘.)") { $0.lineStyle(.quote) }
            separator
            tool("link", "Link (⌘K)") { $0.link() }
            tool("link.badge.plus", "Link to another note, [[Note]] (⇧⌘K)") { $0.wikilink() }
            Menu {
                Button("Plain code block  ⌥⌘C") { controller.run { $0.codeBlock() } }
                Divider()
                ForEach(Self.languages, id: \.id) { lang in
                    Button(lang.name) { controller.run { $0.codeBlock(lang.id) } }
                }
            } label: {
                Label("Code block", systemImage: "curlybraces")
            } primaryAction: {
                controller.run { $0.codeBlock() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Code block (⌥⌘C). Use the arrow to pick a language for syntax colours")
            tool("photo", "Insert image. You can also paste (⌘V) or drop images into the note") { $0.insertImageFromFile() }
            tool("tablecells", "Table") {
                $0.block("| Column | Column |\n| --- | --- |\n|  |  |\n", caret: 2, select: 6)
            }
            tool("minus", "Divider") { $0.block("---\n") }
            separator
            Menu {
                ForEach(Self.sections, id: \.name) { s in
                    Button(s.name) { controller.run { $0.block(s.text, caret: s.caret) } }
                }
                Divider()
                Button("Tip callout") { controller.run { $0.block("> [!tip]\n> \n", caret: 11) } }
                Button("Warning callout") { controller.run { $0.block("> [!warning]\n> \n", caret: 15) } }
            } label: {
                Label("Insert Section", systemImage: "plus.square.on.square")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Insert a ready-made section at the cursor")

            Spacer()
            tool("magnifyingglass", "Find (⌘F)") { $0.showFind() }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    private var separator: some View {
        Divider().frame(height: 16).padding(.horizontal, 6)
    }

    private func tool(_ icon: String, _ help: String, _ action: @escaping (MarkdownNSTextView) -> Void) -> some View {
        Button { controller.run(action) } label: {
            Image(systemName: icon).frame(width: 26, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    static let languages: [(name: String, id: String)] = [
        ("Swift", "swift"), ("Python", "python"), ("JavaScript", "js"), ("TypeScript", "ts"), ("Java", "java"),
        ("Kotlin", "kotlin"), ("C", "c"), ("C++", "cpp"), ("C#", "csharp"), ("Go", "go"), ("Rust", "rust"),
        ("Ruby", "ruby"), ("PHP", "php"), ("SQL", "sql"), ("Shell", "bash"), ("JSON", "json"), ("YAML", "yaml"),
        ("HTML", "html"), ("CSS", "css"),
    ]

    /// Ready-made sections; `caret` is where the cursor lands inside the text.
    static let sections: [(name: String, text: String, caret: Int?)] = [
        ("Key points", "## Key points\n- \n", 16),
        ("Steps", "## Steps\n1. \n", 12),
        ("Definition", "## Definition\n> \n", 16),
        ("Example", "## Example\n\n", 11),
        ("Code", "## Code\n```\n\n```\n", 12),
        ("Complexity", "## Complexity\n- Time: \n- Space: \n", 22),
        ("Mistakes I made", "## Mistakes I made\n- \n", 21),
        ("Self-check questions", "## Self-check\n- [ ] \n", 20),
        ("Summary", "## Summary\n\n", 11),
    ]
}
