import AppKit
import CoachCore

/// Images pasted or dropped into notes. They're saved where Obsidian would put them (its
/// "Default location for new attachments" setting), or in `Coach/Attachments` when that isn't set,
/// and embedded as `![[Pasted image 20261107093000.png]]`, so Obsidian shows them too.
@MainActor
final class AttachmentStore {
    nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "svg"]

    let vault: URL
    let coachRoot: URL
    /// Lower-cased file name → files with that name anywhere in the vault (Obsidian links by name).
    private var index: [String: [URL]] = [:]
    private var indexedAt: Date?

    init(vault: URL, coachRoot: URL) {
        self.vault = vault
        self.coachRoot = coachRoot
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    nonisolated static func isImage(_ name: String) -> Bool {
        imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    // MARK: Saving

    /// Folder for new attachments of `note`, following Obsidian's `attachmentFolderPath`:
    /// "/" = vault root, "./" = next to the note, "./x" = subfolder next to the note, "x" = vault folder.
    func folder(for note: URL) -> URL {
        let config = vault.appendingPathComponent(".obsidian/app.json")
        let setting = (try? Data(contentsOf: config))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["attachmentFolderPath"] as? String
        guard let setting, !setting.isEmpty else { return coachRoot.appendingPathComponent("Attachments", isDirectory: true) }
        let noteFolder = note.deletingLastPathComponent()
        if setting == "/" { return vault }
        if setting == "./" || setting == "." { return noteFolder }
        if setting.hasPrefix("./") { return noteFolder.appendingPathComponent(String(setting.dropFirst(2)), isDirectory: true) }
        return vault.appendingPathComponent(setting, isDirectory: true)
    }

    /// Writes the image and returns the name to embed. `name` (without extension) is used for dropped
    /// files; pasted images are called "Pasted image <date>" like in Obsidian.
    func save(_ data: Data, ext: String, name: String?, for note: URL) throws -> String {
        let folder = folder(for: note)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refreshIndexIfStale(force: indexedAt == nil)

        let stamp = Self.stampFormatter.string(from: Date())
        let base = name.map(VaultScanner.sanitizeFileName).flatMap { $0.isEmpty ? nil : $0 } ?? "Pasted image \(stamp)"
        var fileName = "\(base).\(ext)"
        var n = 1
        // Unique in the whole vault, so the short ![[name]] link always finds this file.
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
                || index[fileName.lowercased()] != nil {
            fileName = "\(base) \(n).\(ext)"
            n += 1
        }
        let url = folder.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        index[fileName.lowercased(), default: []].append(url)
        return fileName
    }

    // MARK: Finding

    /// Finds the file an embed points at: `![[name.png]]`, `![[folder/name.png]]` or `![](../x.png)`.
    func resolve(_ rawTarget: String, from note: URL?) -> URL? {
        var target = rawTarget.trimmingCharacters(in: .whitespaces)
        if target.hasPrefix("<"), target.hasSuffix(">") { target = String(target.dropFirst().dropLast()) }
        target = target.removingPercentEncoding ?? target
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        guard !target.isEmpty, !target.contains("://") else { return nil }

        let fm = FileManager.default
        var candidates: [URL] = []
        if target.hasPrefix("/") { candidates.append(URL(fileURLWithPath: target)) }
        if let note { candidates.append(note.deletingLastPathComponent().appendingPathComponent(target)) }
        candidates.append(vault.appendingPathComponent(target))
        if let note { candidates.append(folder(for: note).appendingPathComponent(target)) }
        if let hit = candidates.first(where: { fm.fileExists(atPath: $0.path) }) { return hit.standardizedFileURL }

        // Obsidian-style lookup by file name anywhere in the vault.
        let name = (target as NSString).lastPathComponent.lowercased()
        func lookup() -> URL? {
            guard let matches = index[name]?.filter({ fm.fileExists(atPath: $0.path) }), !matches.isEmpty else { return nil }
            let suffix = "/" + target.lowercased()
            return matches.first { $0.path.lowercased().hasSuffix(suffix) } ?? matches.first
        }
        if let hit = lookup() { return hit }
        refreshIndexIfStale(force: false)
        return lookup()
    }

    private func refreshIndexIfStale(force: Bool) {
        if !force, let indexedAt, Date().timeIntervalSince(indexedAt) < 5 { return }
        indexedAt = Date()
        var fresh: [String: [URL]] = [:]
        if let e = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in e where url.pathExtension.lowercased() != "md" {
                fresh[url.lastPathComponent.lowercased(), default: []].append(url)
            }
        }
        index = fresh
    }
}

/// Decoded images, reloaded when the file changes.
@MainActor
enum ImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(at url: URL) -> NSImage? {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(mtime)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Reads images off a pasteboard (paste or drag): image files from Finder, or image data from
/// screenshots, Preview, browsers… Text wins: if there's text on the pasteboard, it's not an image paste.
enum PasteboardImages {
    struct Item {
        var data: Data
        var ext: String
        var name: String?
    }

    static func items(on pb: NSPasteboard) -> [Item] {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let images = urls.filter { AttachmentStore.isImage($0.lastPathComponent) }
            if !images.isEmpty, images.count == urls.count {
                return images.compactMap { url in
                    (try? Data(contentsOf: url)).map {
                        Item(data: $0, ext: url.pathExtension.lowercased(), name: url.deletingPathExtension().lastPathComponent)
                    }
                }
            }
            if !urls.isEmpty { return [] } // other files: let the text view insert their paths
        }
        if pb.string(forType: .string) != nil { return [] }
        if let png = pb.data(forType: .png) { return [Item(data: png, ext: "png")] }
        if let jpeg = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) { return [Item(data: jpeg, ext: "jpg")] }
        if let image = NSImage(pasteboard: pb), let png = pngData(image) { return [Item(data: png, ext: "png")] }
        return []
    }

    static func hasImages(_ pb: NSPasteboard) -> Bool {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.allSatisfy { AttachmentStore.isImage($0.lastPathComponent) }
        }
        return pb.string(forType: .string) == nil && pb.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
