import Foundation

/// Parses the "Several files" box: one file per line, optional `| 1`–`| 5` suffix for that file's confidence.
/// List markers (`-`, `*`, `•`, `- [ ]`) are ignored so you can paste a Markdown list.
public enum BatchInput {
    public static func parse(_ text: String, defaultConfidence: Int) -> [(title: String, confidence: Int)] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "• "] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count))
                break
            }
            guard !line.isEmpty else { return nil }
            var confidence = Confidence.clamp(defaultConfidence)
            if let bar = line.lastIndex(of: "|"),
               let c = Int(line[line.index(after: bar)...].trimmingCharacters(in: .whitespaces)),
               Confidence.range.contains(c) {
                confidence = c
                line = line[..<bar].trimmingCharacters(in: .whitespaces)
            }
            return line.isEmpty ? nil : (line, confidence)
        }
    }
}
