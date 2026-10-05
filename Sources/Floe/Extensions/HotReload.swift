//
//  HotReload.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

/// Which open commands restart when a file of their extension is saved, and for which files.
nonisolated enum HotReload {
    /// The folder to watch while a command is open; nil for a prebuilt extension with no `src/`.
    /// Nil for a command without a view too: running it again on a save would do its work twice.
    static func watchedFolder(for command: ExtensionCommand, fileManager: FileManager = .default) -> URL? {
        guard command.source == .local, command.mode == "view" else { return nil }
        var isDirectory: ObjCBool = false
        let sources = command.extensionDir.appendingPathComponent("src").path
        guard fileManager.fileExists(atPath: sources, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return command.extensionDir
    }

    /// Watches the folder of an open command; nil when there is none to watch. `onSave` is handed the
    /// saved paths on the main queue, so it may hold what only the main thread touches.
    static func watcher(for command: ExtensionCommand, onSave: @escaping @MainActor ([String]) -> Void) -> DirectoryWatcher? {
        watchedFolder(for: command).flatMap { folder in
            DirectoryWatcher(
                directory: folder,
                isRelevant: { restarts($0) },
                onChange: { paths in
                    DispatchQueue.main.async { onSave(paths) }
                }
            )
        }
    }

    /// Whether a change to this path, relative to the extension's folder, shows in a restarted command.
    /// A change the watcher could not name counts.
    static func restarts(_ relativePath: String) -> Bool {
        if relativePath == DirectoryWatcher.everything || relativePath == manifest {
            return true
        }
        guard !DirectoryWatcher.isIgnored(relativePath) else { return false }
        return relativePath.hasPrefix("src/") || relativePath.hasPrefix("assets/")
    }

    /// Whether the commands the extension declares may have changed, so the catalog is read again.
    static func changesManifest(_ relativePaths: [String]) -> Bool {
        relativePaths.contains { $0 == manifest || $0 == DirectoryWatcher.everything }
    }

    private static let manifest = "package.json"
}
