//
//  ClipboardCapture.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit

/// What one copy put on the pasteboard, read on the main thread and still unprocessed.
struct ClipboardCapture: Sendable {
    enum Content: Sendable {
        case files([String])
        /// The image as copied; the text is what the copy becomes when the image cannot be decoded.
        case image(Data, fallbackText: String?)
        case text(String)
    }

    var content: Content
    var date: Date
    var sourceApp: String?

    /// The original image data this copy holds until it is converted; text and files are not counted.
    var imageBytes: Int {
        if case let .image(data, _) = content {
            data.count
        } else {
            0
        }
    }

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

    /// Reads the pasteboard once: files first, then images, then text. Nil for what is never saved.
    static func read(_ board: NSPasteboard) -> ClipboardCapture? {
        guard !isPasswordManagerInFront else { return nil }
        let types = Set((board.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: skippedTypes) else { return nil }
        guard let content = content(of: board) else { return nil }
        return ClipboardCapture(content: content, date: Date(), sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName)
    }

    private static func content(of board: NSPasteboard) -> Content? {
        if let objects = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL],
           !objects.isEmpty
        {
            return .files(objects.map { ($0 as URL).path })
        }
        if let data = board.data(forType: .tiff) ?? board.data(forType: .png) {
            return .image(data, fallbackText: board.string(forType: .string))
        }
        return board.string(forType: .string).map(Content.text)
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
}

extension ClipboardEntry {
    /// The entry for copied files.
    static func files(_ paths: [String], date: Date, sourceApp: String?) -> ClipboardEntry {
        ClipboardEntry(id: UUID(), kind: .file, filePaths: paths, date: date, pinned: false, sourceApp: sourceApp)
    }

    /// The entry for copied text: a web address is a link and keeps no surrounding space. Nil when empty.
    static func text(_ string: String, date: Date, sourceApp: String?) -> ClipboardEntry? {
        guard !string.isEmpty else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed)
        if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", !(url.host ?? "").isEmpty {
            return ClipboardEntry(id: UUID(), kind: .link, text: trimmed, date: date, pinned: false, sourceApp: sourceApp)
        }
        let kind: Kind = url?.scheme == "file" ? .link : .text
        return ClipboardEntry(id: UUID(), kind: kind, text: string, date: date, pinned: false, sourceApp: sourceApp)
    }

    /// The entry for a stored image; duplicates are told apart by the start of the PNG.
    static func image(named name: String, png: Data, date: Date, sourceApp: String?) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), kind: .image, text: png.prefix(64).base64EncodedString(), imageFile: name, date: date, pinned: false, sourceApp: sourceApp
        )
    }
}
