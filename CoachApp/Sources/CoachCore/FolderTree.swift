import Foundation

/// A folder inside Coach/. Folders are never rated. Their statistics are rolled up from the files inside them.
public struct FolderNode: Identifiable, Hashable, Sendable {
    public var name: String
    /// Path relative to the Coach folder. `[]` is the Coach folder itself.
    public var path: [String]
    public var children: [FolderNode]
    /// Tracked files directly in this folder.
    public var files: [Topic]
    /// Markdown files directly in this folder that aren't tracked yet.
    public var untracked: [URL]

    public init(name: String, path: [String], children: [FolderNode], files: [Topic], untracked: [URL]) {
        self.name = name
        self.path = path
        self.children = children
        self.files = files
        self.untracked = untracked
    }

    public var id: String { "/" + path.joined(separator: "/") }
    public var isRoot: Bool { path.isEmpty }
    /// For OutlineGroup: nil means "leaf" (no disclosure triangle).
    public var childrenOrNil: [FolderNode]? { children.isEmpty ? nil : children }

    /// Every tracked file in this folder and all subfolders.
    public var allFiles: [Topic] { files + children.flatMap(\.allFiles) }
    public var allUntrackedCount: Int { untracked.count + children.reduce(0) { $0 + $1.allUntrackedCount } }

    public func node(at path: [String]) -> FolderNode? {
        guard path.starts(with: self.path) else { return nil }
        if path == self.path { return self }
        for child in children { if let n = child.node(at: path) { return n } }
        return nil
    }

    /// This folder and every folder below it, depth-first (for folder pickers).
    public var flattened: [FolderNode] { [self] + children.flatMap(\.flattened) }

    public func stats(now: Date = Date()) -> FolderStats { FolderStats(files: allFiles, untracked: allUntrackedCount, now: now) }
}

public struct FolderStats: Equatable, Sendable {
    public let fileCount: Int
    public let untrackedCount: Int
    /// Mean confidence of all files inside (any depth). nil when the folder has no files.
    public let averageConfidence: Double?
    /// Number of files at each confidence level, index 0 = confidence 1 … index 4 = confidence 5.
    public let distribution: [Int]
    public let dueCount: Int
    public let overdueCount: Int
    public let neverRevisedCount: Int
    public let lastRevised: Date?
    /// Lowest confidence first, then most urgent.
    public let weakest: [Topic]

    public var coverage: Double? {
        let total = fileCount + untrackedCount
        return total == 0 ? nil : Double(fileCount) / Double(total)
    }

    public init(files: [Topic], untracked: Int = 0, now: Date = Date()) {
        fileCount = files.count
        untrackedCount = untracked
        averageConfidence = files.isEmpty ? nil : Double(files.reduce(0) { $0 + $1.confidence }) / Double(files.count)
        var d = [0, 0, 0, 0, 0]
        for f in files { d[Confidence.clamp(f.confidence) - 1] += 1 }
        distribution = d
        dueCount = files.filter { $0.isDue(now: now) }.count
        overdueCount = files.filter { $0.daysUntilDue(now: now) < 0 }.count
        neverRevisedCount = files.filter { $0.lastReviewed == nil }.count
        lastRevised = files.compactMap(\.lastReviewed).max()
        weakest = Array(files.sorted {
            $0.confidence != $1.confidence ? $0.confidence < $1.confidence : Topic.urgency($0, $1)
        }.prefix(3))
    }
}

public enum FolderTree {
    /// Builds the folder tree for the Coach folder from a scan.
    public static func build(rootName: String, root: URL, topics: [Topic], untracked: [URL], folders: [[String]]) -> FolderNode {
        final class Builder {
            let name: String, path: [String]
            var children: [String: Builder] = [:]
            var files: [Topic] = []
            var untracked: [URL] = []
            init(name: String, path: [String]) { self.name = name; self.path = path }

            func at(_ path: [String]) -> Builder {
                var node = self
                for (i, part) in path.enumerated() {
                    if let next = node.children[part] { node = next; continue }
                    let next = Builder(name: part, path: Array(path[...i]))
                    node.children[part] = next
                    node = next
                }
                return node
            }

            func freeze() -> FolderNode {
                FolderNode(
                    name: name, path: path,
                    children: children.values.map { $0.freeze() }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    files: files.sorted(by: Topic.urgency),
                    untracked: untracked.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                )
            }
        }

        let tree = Builder(name: rootName, path: [])
        for f in folders { _ = tree.at(f) }
        for t in topics { tree.at(t.folder).files.append(t) }
        for u in untracked { tree.at(Topic.relativeFolder(of: u, in: root)).untracked.append(u) }
        return tree.freeze()
    }
}
