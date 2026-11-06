import CoachCore
import SwiftUI

enum SidebarItem: Hashable {
    case due, upcoming, critical, all, subject(String), untracked
}

struct ContentView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.vaultURL == nil {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct MainView: View {
    @Environment(VaultStore.self) private var store
    @State private var sidebar: SidebarItem? = .due
    @State private var search = ""
    @State private var selectedNote: URL?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $sidebar) {
                Section("Revise") {
                    row("Due Today", "checklist", .due, count: store.dueCount)
                    row("Next 7 Days", "calendar", .upcoming)
                    row("Critical (1–2)", "exclamationmark.triangle", .critical,
                        count: store.topics.filter { $0.confidence <= 2 }.count)
                    row("All Topics", "books.vertical", .all, count: store.topics.count)
                }
                if !store.subjects.isEmpty {
                    Section("Subjects") {
                        ForEach(store.subjects, id: \.self) { s in
                            row(s, "folder", .subject(s), count: store.topics.filter { $0.subjectName == s }.count)
                        }
                    }
                }
                Section("Vault") {
                    row("Other Notes", "doc.badge.plus", .untracked, count: store.untrackedNotes.count)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } content: {
            Group {
                if sidebar == .untracked {
                    UntrackedListView(search: search, selection: $selectedNote)
                } else {
                    TopicListView(filter: sidebar ?? .due, search: search)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if sidebar == .untracked {
                if let selectedNote {
                    TrackNoteView(url: selectedNote) { id in
                        sidebar = .all
                        store.selectedTopicID = id
                        self.selectedNote = nil
                    }
                    .id(selectedNote)
                } else {
                    ContentUnavailableView("Pick a note to track", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Any note in your vault can become a Coach topic."))
                }
            } else if let topic = store.topic(id: store.selectedTopicID) {
                TopicDetailView(topic: topic)
            } else {
                ContentUnavailableView("No topic selected", systemImage: "brain.head.profile",
                                       description: Text(store.dueCount > 0
                                                         ? "\(store.dueCount) topic\(store.dueCount == 1 ? " is" : "s are") waiting. Press ⌘R to start reviewing."
                                                         : "You're all caught up. Add a topic with ⌘N."))
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search topics")
        .navigationTitle("Coach")
        .toolbar {
            ToolbarItemGroup {
                if store.isScanning { ProgressView().controlSize(.small) }
                Button { store.presentedSheet = .review } label: {
                    Label("Review \(store.dueCount)", systemImage: "play.fill")
                }
                .help("Review everything due today (⌘R)")
                .disabled(store.dueCount == 0)

                Button { store.presentedSheet = .addTopic } label: {
                    Label("New Topic", systemImage: "plus")
                }
                .help("Add a topic (⌘N)")
            }
        }
        .sheet(item: $store.presentedSheet) { sheet in
            switch sheet {
            case .addTopic: AddTopicView()
            case .review: ReviewSessionView()
            }
        }
    }

    private func row(_ title: String, _ icon: String, _ item: SidebarItem, count: Int? = nil) -> some View {
        Label(title, systemImage: icon)
            .badge(count ?? 0)
            .tag(item)
    }
}

struct TopicListView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let filter: SidebarItem
    let search: String

    var topics: [Topic] {
        let now = store.now
        var list: [Topic]
        switch filter {
        case .due: list = store.topics.filter { $0.isDue(now: now) }
        case .upcoming: list = store.topics.filter { (1...7).contains($0.daysUntilDue(now: now)) }
        case .critical: list = store.topics.filter { $0.confidence <= 2 }
        case .all, .untracked: list = store.topics
        case .subject(let s): list = store.topics.filter { $0.subjectName == s }
        }
        if !search.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.subjectName.localizedCaseInsensitiveContains(search) }
        }
        return list.sorted(by: Topic.urgency)
    }

    var body: some View {
        @Bindable var store = store
        let topics = self.topics
        if topics.isEmpty {
            ContentUnavailableView {
                Label(filter == .due ? "Nothing due" : "No topics", systemImage: filter == .due ? "checkmark.seal" : "tray")
            } description: {
                Text(filter == .due ? "Nice work, you're caught up for today." : "Add one with the + button.")
            }
        } else {
            List(topics, selection: $store.selectedTopicID) { topic in
                TopicRow(topic: topic, now: store.now)
                    .tag(topic.id)
            }
            // Right-click menu, and double-click (or Return) opens the dedicated revision page.
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let topic = store.topic(id: id) { TopicMenu(topic: topic) }
            } primaryAction: { ids in
                if let id = ids.first { openWindow.revise(id) }
            }
        }
    }
}

struct TopicRow: View {
    let topic: Topic
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(topic.subjectName)
                    Text("·")
                    DueLabel(topic: topic, now: now)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            ConfidenceBadge(confidence: topic.confidence, showLabel: false)
        }
        .padding(.vertical, 3)
    }
}

/// Shared actions for a topic (context menu and detail view).
struct TopicMenu: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let topic: Topic

    var body: some View {
        Button("Revise Now") { openWindow.revise(topic.id) }
        Divider()
        Menu("Mark Reviewed") {
            ForEach(Array(Confidence.range), id: \.self) { c in
                Button("\(c) · \(Confidence.label(c))") { store.review(topic, confidence: c) }
            }
        }
        Menu("Postpone") {
            Button("1 day") { store.postpone(topic, days: 1) }
            Button("3 days") { store.postpone(topic, days: 3) }
            Button("1 week") { store.postpone(topic, days: 7) }
        }
        Divider()
        Button("Open in Obsidian") { store.openInObsidian(topic.url) }
        Button("Reveal in Finder") { store.revealInFinder(topic.url) }
        Divider()
        Button("Stop Tracking", role: .destructive) { store.untrack(topic) }
    }
}

struct UntrackedListView: View {
    @Environment(VaultStore.self) private var store
    let search: String
    @Binding var selection: URL?

    var body: some View {
        let notes = search.isEmpty ? store.untrackedNotes
            : store.untrackedNotes.filter { store.relativePath($0).localizedCaseInsensitiveContains(search) }
        if notes.isEmpty {
            ContentUnavailableView("No other notes", systemImage: "doc",
                                   description: Text("Every Markdown note in the vault is already tracked."))
        } else {
            List(notes, id: \.self, selection: $selection) { url in
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent).lineLimit(1)
                    Text(store.relativePath(url.deletingLastPathComponent()))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(url)
            }
        }
    }
}
