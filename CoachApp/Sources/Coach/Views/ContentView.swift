import CoachCore
import SwiftUI

enum SidebarItem: Hashable {
    /// The whole garden drawn as one tree.
    case overview
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
        .tint(Garden.leaf)
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
                Label("Garden Overview", systemImage: "tree").tag(SidebarItem.overview)
                Section("Watering") {
                    row("Today", "drop", .due, count: store.todayCount)
                    row("Next 7 Days", "sun.max", .upcoming,
                        count: store.topics.filter { (1...7).contains($0.daysUntilDue(now: store.now)) }.count)
                    row("Seeds & Sprouts (1–2)", "leaf", .critical,
                        count: store.topics.filter { $0.confidence <= 2 }.count)
                }
                Section("Garden") {
                    OutlineGroup([tree], children: \.childrenOrNil) { node in
                        FolderSidebarRow(node: node, now: store.now)
                            .tag(SidebarItem.folder(node.path))
                            .contextMenu {
                                Button("Plant Files…") { store.presentedSheet = .addTopic(folder: node.path) }
                                Button("New Bed…") { store.presentedSheet = .newFolder(parent: node.path) }
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
                case .overview:
                    GardenOverviewView(sidebar: $sidebar)
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
                ContentUnavailableView("Pick a plant", systemImage: "leaf",
                                       description: Text(store.todayCount > 0
                                                         ? "\(Garden.plants(store.todayCount)) to water today. Press ⌘R to start."
                                                         : store.topics.isEmpty ? "Plant your first file with ⌘N." : "The garden is watered for today. 🌤️"))
            }
        }
        // The selection is shared by every list: when you switch lists, keep it only if that file is shown there.
        .onChange(of: sidebar) { _, new in
            if !isShown(store.selectedTopicID, in: new ?? .due) { store.selectedTopicID = nil }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search the garden")
        .navigationTitle("Coach")
        .toolbar {
            ToolbarItemGroup {
                if store.isScanning { ProgressView().controlSize(.small) }
                Button { store.presentedSheet = .review } label: {
                    Label("Water \(store.reviewQueue.count)", systemImage: "drop.fill")
                }
                .help("Water today's plants (⌘R)")
                .disabled(store.reviewQueue.isEmpty)

                Button { store.presentedSheet = .newFolder(parent: currentFolder) } label: {
                    Label("New Bed", systemImage: "square.grid.3x3")
                }
                .help("Create a garden bed: a folder for a subject, topic or subtopic")

                Button { store.presentedSheet = .addTopic(folder: nil) } label: {
                    Label("Plant", systemImage: "plus")
                }
                .help("Plant new files to revise (⌘N)")
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
        case .overview: return true // every tracked file is a leaf on the tree
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
            Label(node.name, systemImage: node.isRoot ? "tree" : "leaf")
                .lineLimit(1)
            Spacer(minLength: 4)
            if let avg = stats.averageConfidence {
                Text(String(format: "%.1f", avg))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Confidence.color(Int(avg.rounded())))
                    .help("Average growth of the \(Garden.plants(stats.fileCount)) in this bed")
            }
            if stats.dueCount > 0 {
                Text("\(stats.dueCount)")
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Garden.sun.opacity(0.25), in: Capsule())
                    .help("\(stats.dueCount) thirsty")
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
                    Label(plan.isGoalMet ? "The garden is watered" : store.topics.isEmpty ? "An empty garden" : "Nothing is thirsty",
                          systemImage: plan.isGoalMet ? "drop.fill" : "leaf")
                } description: {
                    Text(plan.isGoalMet
                         ? "You watered \(Garden.plants(plan.doneToday)) today. 🌻"
                         : store.topics.isEmpty ? "Plant files with the + button." : "No plant needs water. Set a daily goal in Settings to always tend a few.")
                } actions: {
                    if plan.isGoalMet, let next = nextInLine {
                        Button("Water One More: \(next.title)") { openWindow.revise(next.id) }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $store.selectedTopicID) {
                    section("Thirsty", due, footer: nil)
                    section("Water early", ahead,
                            footer: "Not thirsty yet, but next in line. Early watering counts, just a little less.")
                    section(plan.goal > 0 ? "Also thirsty · beyond today's round" : "Thirsty", more,
                            footer: "Still thirsty. Water them if you have time, or they'll lead tomorrow's round.")
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
                Text("💧 \(min(plan.doneToday, plan.goal)) of \(plan.goal) watered today").font(.callout.weight(.semibold))
                Spacer()
                if plan.isGoalMet { Text("🌻") }
            }
            ProgressView(value: Double(min(plan.doneToday, plan.goal)), total: Double(plan.goal))
                .tint(plan.isGoalMet ? Garden.forest : Garden.water)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .help("Daily watering round: \(Garden.plants(plan.goal)). Change it in Settings.")
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
        case .overview: list = store.topics
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
                Label(filter == .due ? "Nothing is thirsty" : "No plants here", systemImage: "leaf")
            } description: {
                Text(filter == .due ? "Nice work, the garden is watered for today." : "Plant files with the + button.")
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
            Text(Garden.stageEmoji(topic.confidence))
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
        Button("Water Now") { openWindow.revise(topic.id) }
        Button("Edit Note…") { openWindow.editNote(topic.id) }
        Divider()
        Menu("Mark Watered") {
            ForEach(Array(Confidence.range), id: \.self) { c in
                Button("\(Garden.stageEmoji(c)) \(c) · \(Garden.stageName(c))") { store.review(topic, confidence: c) }
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
        Button("Uproot (Stop Tracking)", role: .destructive) { store.untrack(topic) }
    }
}
