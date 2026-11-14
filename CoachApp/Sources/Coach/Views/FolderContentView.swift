import CoachCore
import SwiftUI

/// A folder's page: rolled-up statistics, its subfolders, its files, and files not tracked yet.
struct FolderContentView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let path: [String]
    let search: String
    @Binding var sidebar: SidebarItem?

    var body: some View {
        @Bindable var store = store
        if let node = store.tree.node(at: path) {
            let stats = node.stats(now: store.now)
            List(selection: $store.selectedTopicID) {
                Section {
                    FolderStatsCard(node: node, stats: stats, sidebar: $sidebar)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .selectionDisabled()
                }

                if search.isEmpty {
                    if !node.children.isEmpty {
                        Section("Folders") {
                            ForEach(node.children) { child in
                                Button { sidebar = .folder(child.path) } label: {
                                    SubfolderRow(node: child, now: store.now)
                                }
                                .buttonStyle(.plain)
                                .selectionDisabled()
                            }
                        }
                    }
                    Section(node.files.isEmpty ? "Files" : "Files (\(node.files.count))") {
                        if node.files.isEmpty {
                            Text(node.children.isEmpty ? "No files yet. Use “Add Files”." : "No files directly in this folder.")
                                .foregroundStyle(.secondary)
                                .selectionDisabled()
                        }
                        ForEach(node.files) { topic in
                            TopicRow(topic: topic, now: store.now).tag(topic.id)
                        }
                    }
                } else {
                    // Searching: every matching file anywhere in this folder.
                    Section("Matching files") {
                        ForEach(node.allFiles.filter { matches($0, search) }.sorted(by: Topic.urgency)) { topic in
                            TopicRow(topic: topic, now: store.now, showFolder: true).tag(topic.id)
                        }
                    }
                }

                if !node.untracked.isEmpty {
                    Section("Not tracked yet (\(node.untracked.count))") {
                        ForEach(node.untracked, id: \.self) { url in
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.badge.plus")
                                .foregroundStyle(.secondary)
                                .tag(ListSelection.untracked(url))
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let topic = store.topic(id: id) { TopicMenu(topic: topic) }
            } primaryAction: { ids in
                if let id = ids.first, store.topic(id: id) != nil { openWindow.revise(id) }
            }
        } else {
            ContentUnavailableView("Folder not found", systemImage: "folder.badge.questionmark")
        }
    }
}

struct SubfolderRow: View {
    let node: FolderNode
    let now: Date

    var body: some View {
        let s = node.stats(now: now)
        HStack {
            Image(systemName: "folder.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.headline)
                Text("\(s.fileCount) file\(s.fileCount == 1 ? "" : "s")\(s.dueCount > 0 ? " · \(s.dueCount) due" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let avg = s.averageConfidence { AverageBadge(value: avg) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct AverageBadge: View {
    let value: Double
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Confidence.color(Int(value.rounded()))).frame(width: 8, height: 8)
            Text(String(format: "%.1f", value)).font(.caption.weight(.medium)).monospacedDigit()
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Confidence.color(Int(value.rounded())).opacity(0.15), in: Capsule())
        .help("Average confidence of the files inside")
    }
}

struct FolderStatsCard: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    let node: FolderNode
    let stats: FolderStats
    @Binding var sidebar: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Breadcrumb + title
            VStack(alignment: .leading, spacing: 4) {
                if node.path.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(Array(node.path.dropLast().enumerated()), id: \.offset) { i, part in
                            Button(part) { sidebar = .folder(Array(node.path.prefix(i + 1))) }
                                .buttonStyle(.link)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                }
                Text(node.name).font(.title.bold())
            }

            // Actions
            HStack {
                let due = store.dueTopics(in: node.path)
                Button {
                    if let first = due.first { openWindow.revise(first.id, scope: node.path) }
                } label: {
                    Label(due.isEmpty ? "Nothing due" : "Revise \(due.count) due", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(due.isEmpty)
                .help("Go through this folder's due files one by one, most urgent first")
                Button { store.presentedSheet = .addTopic(folder: node.path) } label: {
                    Label("Add Files", systemImage: "doc.badge.plus")
                }
                Button { store.presentedSheet = .newFolder(parent: node.path) } label: {
                    Label("New Subfolder", systemImage: "folder.badge.plus")
                }
            }
            .controlSize(.small)

            if stats.fileCount == 0 {
                Text("No rated files here yet. Folder statistics come from the files inside.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%.1f", stats.averageConfidence ?? 0))
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(Confidence.color(Int((stats.averageConfidence ?? 3).rounded())))
                        Text("avg confidence").font(.caption).foregroundStyle(.secondary)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow { metric("\(stats.fileCount)", "files"); metric("\(stats.dueCount)", "due", stats.dueCount > 0 ? .orange : nil) }
                        GridRow { metric("\(stats.overdueCount)", "overdue", stats.overdueCount > 0 ? .red : nil); metric("\(stats.neverRevisedCount)", "never revised") }
                    }
                }

                DistributionBar(distribution: stats.distribution)

                HStack(spacing: 16) {
                    if let last = stats.lastRevised {
                        Label("Last revised \(last.formatted(.relative(presentation: .named)))", systemImage: "clock")
                    }
                    if let cov = stats.coverage, stats.untrackedCount > 0 {
                        Label("\(Int((cov * 100).rounded()))% tracked (\(stats.untrackedCount) not yet)", systemImage: "chart.pie")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)

                if !stats.weakest.isEmpty, stats.weakest.first!.confidence <= 3 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weakest files").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(stats.weakest.filter { $0.confidence <= 3 }) { t in
                            Button { openWindow.revise(t.id) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(Confidence.color(t.confidence)).frame(width: 7, height: 7)
                                    Text(t.title).lineLimit(1)
                                    if t.folder != node.path {
                                        Text(t.folder.dropFirst(node.path.count).joined(separator: " › "))
                                            .foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(t.confidence)").monospacedDigit().foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .help("Open the revision page")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ value: String, _ label: String, _ color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color ?? .primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// How many files sit at each confidence level.
struct DistributionBar: View {
    let distribution: [Int]

    var body: some View {
        let total = max(distribution.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        if distribution[i] > 0 {
                            Rectangle()
                                .fill(Confidence.color(i + 1))
                                .frame(width: max(4, (geo.size.width - 8) * CGFloat(distribution[i]) / CGFloat(total)))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 3) {
                        Circle().fill(Confidence.color(i + 1)).frame(width: 6, height: 6)
                        Text("\(i + 1): \(distribution[i])").monospacedDigit()
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .help("Number of files at each confidence level")
    }
}
