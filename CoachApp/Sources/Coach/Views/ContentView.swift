import CoachCore
import SwiftUI

enum SidebarItem: Hashable {
    case due, upcoming, critical
    /// A folder inside Coach/. `[]` is the Coach folder itself.
    case folder([String])
}

/// List selection: either a tracked file (its coach_id) or an untracked file ("untracked:<path>").
enum ListSelection {
    static let untrackedPrefix = "untracked:"
    static func untracked(_ url: URL) -> String { untrackedPrefix + url.path }
    static func untrackedURL(_ s: String?) -> URL? {
        guard let s, s.hasPrefix(untrackedPrefix) else { return nil }
        return URL(fileURLWithPath: String(s.dropFirst(untrackedPrefix.count)))
    }
}

struct ContentView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store
        Group {
            if store.vaultURL == nil {
                OnboardingView()
            } else {
                MainView()
            }
        }
        .onAppear {
            Notifier.shared.attach(store: store, openWindow: openWindow)
            StudyBuddy.shared.attach(store: store, openWindow: openWindow)
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

    var body: some View {
        @Bindable var store = store
        let tree = store.tree
        NavigationSplitView {
            List(selection: $sidebar) {
                Section("Revise") {
                    row("Today", "checklist", .due, count: store.todayCount)
                    row("Next 7 Days", "calendar", .upcoming,
                        count: store.topics.filter { (1...7).contains($0.daysUntilDue(now: store.now)) }.count)
                    row("Critical (1–2)", "exclamationmark.triangle", .critical,
                        count: store.topics.filter { $0.confidence <= 2 }.count)
                }
                Section("Library") {
                    OutlineGroup([tree], children: \.childrenOrNil) { node in
                        FolderSidebarRow(node: node, now: store.now)
                            .tag(SidebarItem.folder(node.path))
                            .contextMenu {
                                Button("Add Files…") { store.presentedSheet = .addTopic(folder: node.path) }
                                Button("New Subfolder…") { store.presentedSheet = .newFolder(parent: node.path) }
                                if let url = store.folderURL(node.path) {
                                    Button("Reveal in Finder") { store.revealInFinder(url) }
                                }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
        } content: {
            Group {
                switch sidebar ?? .due {
                case .folder(let path):
                    FolderContentView(path: path, search: search, sidebar: $sidebar)
                case .due:
                    TodayListView(search: search)
                case let filter:
                    TopicListView(filter: filter, search: search)
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            if let url = ListSelection.untrackedURL(store.selectedTopicID) {
                TrackNoteView(url: url) { id in store.selectedTopicID = id }
                    .id(url)
            } else if let topic = store.topic(id: store.selectedTopicID) {
                TopicDetailView(topic: topic)
                    .id(topic.id) // fresh state (note, rating) for every file
            } else {
                ContentUnavailableView("No file selected", systemImage: "brain.head.profile",
                                       description: Text(store.todayCount > 0
                                                         ? "\(store.todayCount) file\(store.todayCount == 1 ? "" : "s") to revise today. Press ⌘R to start."
                                                         : store.topics.isEmpty ? "Add files to revise with ⌘N." : "You're done for today."))
            }
        }
        // The selection is shared by every list: when you switch lists, keep it only if that file is shown there.
        .onChange(of: sidebar) { _, new in
            if !isShown(store.selectedTopicID, in: new ?? .due) { store.selectedTopicID = nil }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search files")
        .navigationTitle("Coach")
        .toolbar {
            ToolbarItemGroup {
                if store.isScanning { ProgressView().controlSize(.small) }
                Button { store.presentedSheet = .review } label: {
                    Label("Review \(store.reviewQueue.count)", systemImage: "play.fill")
                }
                .help("Review today's files (⌘R)")
                .disabled(store.reviewQueue.isEmpty)

                Button { store.presentedSheet = .newFolder(parent: currentFolder) } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("Create a folder (subject, topic or subtopic)")

                Button { store.presentedSheet = .addTopic(folder: nil) } label: {
                    Label("New File", systemImage: "plus")
                }
                .help("Add files to revise (⌘N)")
            }
        }
        .sheet(item: $store.presentedSheet) { sheet in
            switch sheet {
            case .addTopic(let folder): AddTopicView(initialFolder: folder)
            case .newFolder(let parent): NewFolderView(parent: parent) { sidebar = .folder($0) }
            case .review: ReviewSessionView()
            }
        }
    }

    /// Whether the list for `item` shows the file (or untracked note) with this selection id.
    private func isShown(_ id: String?, in item: SidebarItem) -> Bool {
        guard let id else { return true }
        if let url = ListSelection.untrackedURL(id) {
            guard case .folder(let path) = item, let root = store.coachRoot else { return false }
            return Topic.relativeFolder(of: url, in: root) == path
        }
        guard let t = store.topic(id: id) else { return false }
        let now = store.now
        switch item {
        case .due: return store.plan.all.contains { $0.id == t.id }
        case .upcoming: return (1...7).contains(t.daysUntilDue(now: now))
        case .critical: return t.confidence <= 2
        case .folder(let path): return search.isEmpty ? t.folder == path : t.isInside(path)
        }
    }

    private var currentFolder: [String] {
        if case .folder(let p) = sidebar { return p }
        return []
    }

    private func row(_ title: String, _ icon: String, _ item: SidebarItem, count: Int) -> some View {
        Label(title, systemImage: icon).badge(count).tag(item)
    }
}

struct FolderSidebarRow: View {
    let node: FolderNode
    let now: Date

    var body: some View {
        let stats = node.stats(now: now)
        HStack(spacing: 6) {
            Label(node.name, systemImage: node.isRoot ? "books.vertical" : "folder")
                .lineLimit(1)
            Spacer(minLength: 4)
            if let avg = stats.averageConfidence {
                Text(String(format: "%.1f", avg))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Confidence.color(Int(avg.rounded())))
                    .help("Average confidence of the \(stats.fileCount) files inside")
            }
            if stats.dueCount > 0 {
                Text("\(stats.dueCount)")
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.25), in: Capsule())
                    .help("\(stats.dueCount) due")
            }
        }
    }
}

/// Today: due files by priority, topped up with nearly-due ones to the daily goal.
struct TodayListView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let search: String

    var body: some View {
        @Bindable var store = store
        let plan = store.plan
        let keep = { (t: Topic) in search.isEmpty || matches(t, search) }
        let due = plan.due.filter(keep), ahead = plan.ahead.filter(keep), more = plan.moreDue.filter(keep)

        VStack(spacing: 0) {
            if plan.goal > 0 { progress(plan) }
            if due.isEmpty && ahead.isEmpty && more.isEmpty {
                ContentUnavailableView {
                    Label(plan.isGoalMet ? "Today's goal is done" : store.topics.isEmpty ? "No files yet" : "Nothing to revise",
                          systemImage: plan.isGoalMet ? "checkmark.seal" : "tray")
                } description: {
                    Text(plan.isGoalMet
                         ? "You revised \(plan.doneToday) file\(plan.doneToday == 1 ? "" : "s") today."
                         : store.topics.isEmpty ? "Add files with the + button." : "Nothing is due. Set a daily goal in Settings to always get a few files.")
                } actions: {
                    if plan.isGoalMet, let next = nextInLine {
                        Button("Revise One More: \(next.title)") { openWindow.revise(next.id) }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $store.selectedTopicID) {
                    section("Due", due, footer: nil)
                    section("Getting ahead", ahead,
                            footer: "Not due yet, but next in line. Revising early counts, just a little less.")
                    section(plan.goal > 0 ? "Also due · beyond today's goal" : "Due", more,
                            footer: "Still due. Do them if you have time, or they'll lead tomorrow's list.")
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let topic = store.topic(id: id) { TopicMenu(topic: topic) }
                } primaryAction: { ids in
                    if let id = ids.first { openWindow.revise(id) }
                }
            }
        }
    }

    /// The best file to do next once the goal is met: highest priority not revised today.
    private var nextInLine: Topic? {
        let now = store.now
        return store.topics
            .filter { !($0.lastReviewed.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false) }
            .sorted(by: DailyPlan.byPriority(now: now)).first
    }

    @ViewBuilder
    private func section(_ title: String, _ topics: [Topic], footer: String?) -> some View {
        if !topics.isEmpty {
            Section {
                ForEach(topics) { topic in
                    TopicRow(topic: topic, now: store.now, showFolder: true).tag(topic.id)
                }
            } header: {
                Text(title)
            } footer: {
                if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func progress(_ plan: DailyPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(min(plan.doneToday, plan.goal)) of \(plan.goal) done today").font(.callout.weight(.semibold))
                Spacer()
                if plan.isGoalMet { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            ProgressView(value: Double(min(plan.doneToday, plan.goal)), total: Double(plan.goal))
                .tint(plan.isGoalMet ? .green : .accentColor)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .help("Daily goal: \(plan.goal) files. Change it in Settings.")
    }
}

/// Next 7 Days / Critical: file suggestions only.
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
        case .folder(let p): list = store.topics.filter { $0.isInside(p) }
        }
        if !search.isEmpty { list = list.filter { matches($0, search) } }
        return list.sorted(by: Topic.urgency)
    }

    var body: some View {
        @Bindable var store = store
        let topics = self.topics
        if topics.isEmpty {
            ContentUnavailableView {
                Label(filter == .due ? "Nothing due" : "No files", systemImage: filter == .due ? "checkmark.seal" : "tray")
            } description: {
                Text(filter == .due ? "Nice work, you're caught up for today." : "Add files with the + button.")
            }
        } else {
            List(topics, selection: $store.selectedTopicID) { topic in
                TopicRow(topic: topic, now: store.now, showFolder: true)
                    .tag(topic.id)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let topic = store.topic(id: id) { TopicMenu(topic: topic) }
            } primaryAction: { ids in
                if let id = ids.first { openWindow.revise(id) }
            }
        }
    }
}

func matches(_ t: Topic, _ q: String) -> Bool {
    t.title.localizedCaseInsensitiveContains(q) || t.folderDisplay.localizedCaseInsensitiveContains(q)
}

struct TopicRow: View {
    let topic: Topic
    let now: Date
    var showFolder = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    if showFolder {
                        Text(topic.folderDisplay).lineLimit(1)
                        Text("·")
                    }
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

/// Shared actions for a file (context menu and detail view).
struct TopicMenu: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let topic: Topic

    var body: some View {
        Button("Revise Now") { openWindow.revise(topic.id) }
        Button("Edit Note…") { openWindow.editNote(topic.id) }
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
