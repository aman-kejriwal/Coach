import Foundation

public struct ScanResult: Sendable {
    public var topics: [Topic] = []
    public var untracked: [URL] = []
    /// Notes whose coach_id repeats an earlier one (usually a copied note). They need a fresh id.
    public var duplicateIDs: [URL] = []
}

public enum VaultScanner {
    /// Walks the vault, skipping hidden folders such as `.obsidian` and `.trash`.
    /// iCloud placeholders (`.Note.md.icloud`) are asked to download so they show up on the next scan.
    public static func scan(root: URL) -> ScanResult {
        var result = ScanResult()
        var seen = Set<String>()
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
            guard !isDir, url.pathExtension.lowercased() == "md",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            if let topic = Topic(document: NoteDocument(text: text), url: url) {
                if seen.insert(topic.id).inserted {
                    result.topics.append(topic)
                } else {
                    result.duplicateIDs.append(url)
                }
            } else {
                result.untracked.append(url)
            }
        }
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
