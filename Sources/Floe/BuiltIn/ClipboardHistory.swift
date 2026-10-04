//
//  ClipboardHistory.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Algorithms
import AppKit
import ApplicationServices
import Combine

/// One saved clipboard item: text, a link, an image or a set of files.
struct ClipboardEntry: Identifiable, Codable {
    enum Kind: String, Codable {
        case text, link, image, file
    }

    var id: UUID
    var kind: Kind
    var text: String?
    var filePaths: [String]?
    var imageFile: String?
    var date: Date
    var pinned: Bool
    var sourceApp: String?

    /// What identifies a duplicate for merging: same kind and same content.
    var identity: String {
        switch kind {
        case .text, .link:
            return "\(kind.rawValue):\(text ?? "")"
        case .file:
            return "file:\((filePaths ?? []).joined(separator: "\n"))"
        case .image:
            return "image:\(text ?? "")"
        }
    }

    var title: String {
        switch kind {
        case .text, .link:
            let first = (text ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return String(first.prefix(120))
        case .file:
            let paths = filePaths ?? []
            if paths.count == 1 {
                return URL(fileURLWithPath: paths[0]).lastPathComponent
            }
            return "\(paths.count) files"
        case .image:
            return "Image"
        }
    }
}

/// Remembers what was on the clipboard: text, links, images and files.
///
/// Concealed, transient and auto-generated pasteboard types are skipped, as is
/// anything copied while a password manager is in front. Pins survive the
/// 300-item cap and Clear; a repeat of what's already saved merges to the top.
/// Entries live under Application Support/Floe/Clipboard with a private
/// 0700 directory and 0600 files; images are downscaled and the folder is
/// capped at 200 MB.
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    static let maxEntries = 300
    static let maxBytes: Int = 200 * 1024 * 1024
    static let imageMaxDimension: CGFloat = 1024

    private static let skippedTypes: Set<String> = [
        "org.nspasteboard.concealed-type",
        "org.nspasteboard.transient-type",
        "org.nspasteboard.auto-generated-type",
    ]

    private static let passwordManagerPrefixes = [
        "com.1password",
        "com.bitwarden",
        "org.keepassxc",
        "com.lastpass",
        "com.dashlane",
        "com.enpass",
        "com.roboform",
        "com.strongbox",
    ]

    private static let passwordManagerNames = [
        "1password", "bitwarden", "keepass", "lastpass", "dashlane", "enpass", "roboform", "strongbox",
    ]

    @Published private(set) var entries: [ClipboardEntry] = []

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: Timer?

    static var directory: URL {
        Paths.support.appendingPathComponent("Clipboard", isDirectory: true)
    }

    private static var storeFile: URL {
        directory.appendingPathComponent("history.json")
    }

    init() {
        load()
        startMonitoring()
    }

    // MARK: Monitoring

    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard AppSettings.shared.clipboardHistoryEnabled else { return }
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        guard !Self.isPasswordManagerInFront else { return }
        let types = Set((board.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.skippedTypes) else { return }
        guard let entry = Self.snapshot(board) else { return }
        insert(entry)
    }

    private static var isPasswordManagerInFront: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if let id = app.bundleIdentifier?.lowercased(),
           passwordManagerPrefixes.contains(where: { id.hasPrefix($0) })
        {
            return true
        }
        let name = (app.localizedName ?? "").lowercased()
        return passwordManagerNames.contains { name.contains($0) }
    }

    /// Reads the pasteboard once: files first, then images, then text (links included).
    private static func snapshot(_ board: NSPasteboard) -> ClipboardEntry? {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        if let objects = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
           !objects.isEmpty
        {
            return ClipboardEntry(
                id: UUID(),
                kind: .file,
                text: nil,
                filePaths: objects.map { ($0 as URL).path },
                imageFile: nil,
                date: Date(),
                pinned: false,
                sourceApp: sourceApp
            )
        }
        if let data = board.data(forType: .tiff) ?? board.data(forType: .png),
           let image = NSImage(data: data),
           let png = downscaledPNG(image)
        {
            let name = "\(UUID().uuidString).png"
            ensureDirectory()
            let url = directory.appendingPathComponent(name)
            do {
                try png.write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                return nil
            }
            let hash = png.prefix(64).base64EncodedString()
            return ClipboardEntry(
                id: UUID(),
                kind: .image,
                text: hash,
                filePaths: nil,
                imageFile: name,
                date: Date(),
                pinned: false,
                sourceApp: sourceApp
            )
        }
        guard let string = board.string(forType: .string), !string.isEmpty else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", !url.host.isNilOrEmpty
        {
            return ClipboardEntry(
                id: UUID(),
                kind: .link,
                text: trimmed,
                filePaths: nil,
                imageFile: nil,
                date: Date(),
                pinned: false,
                sourceApp: sourceApp
            )
        }
        return ClipboardEntry(
            id: UUID(),
            kind: kindForText(string),
            text: string,
            filePaths: nil,
            imageFile: nil,
            date: Date(),
            pinned: false,
            sourceApp: sourceApp
        )
    }

    private static func kindForText(_ string: String) -> ClipboardEntry.Kind {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "file" {
            return .link
        }
        return .text
    }

    // MARK: Mutations

    /// Adds an entry, merging a duplicate to the top and keeping its pin.
    func insert(_ entry: ClipboardEntry) {
        var next = entry
        if let existing = entries.first(where: { $0.identity == next.identity }) {
            next.pinned = existing.pinned
            next.id = existing.id
            if existing.kind == .image, existing.imageFile != next.imageFile {
                removeImageFile(existing.imageFile)
            }
            entries.removeAll { $0.id == existing.id }
        }
        entries.insert(next, at: 0)
        enforceEntryCap()
        enforceByteCap()
        save()
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
        save()
    }

    func delete(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        removeImageFile(entries[index].imageFile)
        entries.remove(at: index)
        save()
    }

    /// Removes everything not pinned; pins survive Clear.
    func clear() {
        for entry in entries where !entry.pinned {
            removeImageFile(entry.imageFile)
        }
        entries = entries.filter(\.pinned)
        save()
    }

    private func enforceEntryCap() {
        guard entries.count > Self.maxEntries else { return }
        var (unpinned, pinned) = entries.partitioned(by: \.pinned)
        unpinned = Array(unpinned.prefix(max(0, Self.maxEntries - pinned.count)))
        let removed = Set(entries.map(\.id)).subtracting(pinned.map(\.id) + unpinned.map(\.id))
        for entry in entries where removed.contains(entry.id) {
            removeImageFile(entry.imageFile)
        }
        entries = pinned + unpinned
        entries.sort { $0.date > $1.date }
    }

    /// Drops the oldest unpinned entries (and their images) until the folder fits 200 MB.
    private func enforceByteCap() {
        func totalBytes() -> Int {
            let manager = FileManager.default
            guard let items = try? manager.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            return items.reduce(0) { sum, url in
                sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        guard totalBytes() > Self.maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) where !entry.pinned {
            removeImageFile(entry.imageFile)
            entries.removeAll { $0.id == entry.id }
            if totalBytes() <= Self.maxBytes {
                break
            }
        }
    }

    // MARK: Pasteboard

    /// Writes an entry back to the general pasteboard.
    @discardableResult
    static func writeToPasteboard(_ entry: ClipboardEntry) -> Bool {
        let board = NSPasteboard.general
        board.clearContents()
        switch entry.kind {
        case .text, .link:
            guard let text = entry.text else { return false }
            return board.setString(text, forType: .string)
        case .file:
            let urls = (entry.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            board.writeObjects(urls)
            return true
        case .image:
            guard let name = entry.imageFile,
                  let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let image = NSImage(data: data)
            else { return false }
            board.writeObjects([image])
            return true
        }
    }

    /// Whether Return pastes straight into the frontmost app: needs Accessibility.
    static var canPasteDirectly: Bool {
        AXIsProcessTrusted()
    }

    /// Presses Command-V, so the just-copied entry lands in the frontmost app.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Storage

    private static func ensureDirectory() {
        let dir = directory
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    private func load() {
        Self.ensureDirectory()
        guard let data = try? Data(contentsOf: Self.storeFile),
              let stored = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = stored.filter { entry in
            guard entry.kind == .image, let name = entry.imageFile else { return true }
            return FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent(name).path)
        }
    }

    private func save() {
        Self.ensureDirectory()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try data.write(to: Self.storeFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.storeFile.path)
        } catch {
            // The history is a cache; a failed write is picked up on the next change.
        }
    }

    private func removeImageFile(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(name))
    }

    /// Scales an image to at most `imageMaxDimension` on its longer side and returns PNG data.
    static func downscaledPNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let longest = max(width, height)
        if longest <= Int(imageMaxDimension), let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        let scale = imageMaxDimension / CGFloat(longest)
        let size = NSSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        scaled.unlockFocus()
        guard let scaledTIFF = scaled.tiffRepresentation,
              let scaledRep = NSBitmapImageRep(data: scaledTIFF)
        else { return nil }
        return scaledRep.representation(using: .png, properties: [:])
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let name = entry.imageFile else { return nil }
        return NSImage(contentsOf: Self.directory.appendingPathComponent(name))
    }
}

private extension String? {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
