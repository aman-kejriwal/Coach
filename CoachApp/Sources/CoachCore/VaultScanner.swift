import Foundation

public struct ScanResult: Sendable {
    public var topics: [Topic] = []
    public var untracked: [URL] = []
    /// Every folder inside the root (relative paths), including empty ones, so new folders show up in the tree.
    public var folders: [[String]] = []
    /// Notes whose coach_id repeats an earlier one (usually a copied note). They need a fresh id.
    public var duplicateIDs: [URL] = []
}

public enum VaultScanner {
    /// Walks the Coach folder, skipping hidden folders such as `.obsidian` and `.trash`.
    /// iCloud placeholders (`.Note.md.icloud`) are asked to download so they show up on the next scan.
    public static func scan(root: URL) -> ScanResult {
        var result = ScanResult()
        var seen = Set<String>()
        var foldersWithNotes = Set<[String]>()  // a note somewhere inside
        var foldersWithFiles = Set<[String]>()  // some other file (an image…) somewhere inside
        func markAncestors(of folder: [String], in set: inout Set<[String]>) {
            for i in 0...folder.count { set.insert(Array(folder.prefix(i))) }
        }
        let fm = FileManager.default
        guard let e = fm.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]
        ) else { return result }

        for case let url as URL in e {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if name.hasPrefix(".") {
                if isDir { e.skipDescendants() }
                if name.hasSuffix(".md.icloud") { try? fm.startDownloadingUbiquitousItem(at: url) }
                continue
            }
            if isDir {
                result.folders.append(Topic.relativeFolder(of: url.appendingPathComponent("x"), in: root))
                continue
            }
            let folder = Topic.relativeFolder(of: url, in: root)
            if url.pathExtension.lowercased() != "md" {
                markAncestors(of: folder, in: &foldersWithFiles)
                continue
            }
            markAncestors(of: folder, in: &foldersWithNotes)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            if let topic = Topic(document: NoteDocument(text: text), url: url, coachRoot: root) {
                if seen.insert(topic.id).inserted {
                    result.topics.append(topic)
                } else {
                    result.duplicateIDs.append(url)
                }
            } else {
                result.untracked.append(url)
            }
        }
        // Attachment folders (images but no notes) stay out of the folder tree.
        result.folders.removeAll { foldersWithFiles.contains($0) && !foldersWithNotes.contains($0) }
        result.untracked.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return result
    }

    /// Characters Obsidian can't use in note names or links.
    public static func sanitizeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String(cleaned.prefix(120))
    }
}
