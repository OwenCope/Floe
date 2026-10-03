//
//  DirectoryWatcher.swift
//  Project: Droppy Code
//
//  Copyright (Droppy Code) © 2026 Jordy Spruit
//  Droppy Code by Jordy Spruit (Droppy), https://getdroppycode.app
//  Licensed under the GNU AGPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Droppy Code's Services/Git/WorkingTreeWatch.swift, and modified: only the
//  FSEvents stream over a directory tree is kept. The snapshots, the cookie files and the count of
//  writes since the last snapshot are left out, because they serve an agent's git checkpoints and
//  Floe has none. In their place the watcher reports the changed paths, once they settle, and
//  skips dependencies and hidden entries.

import CoreServices
import Foundation

/// Reports what changed under a directory tree, from an FSEvents stream over it.
/// Changes wait until none has arrived for `debounce`: an editor makes one save of several writes.
final class DirectoryWatcher: Sendable {
    /// Stands for the whole tree in a report, when the stream may have lost events.
    static let everything = "."

    private let core: Core

    /// Nil when the stream cannot be started. `onChange` is handed the changed paths relative to
    /// the directory, sorted, on a queue of the watcher's own.
    init?(
        directory: URL,
        debounce: TimeInterval = 0.3,
        isRelevant: @escaping @Sendable (String) -> Bool = { !DirectoryWatcher.isIgnored($0) },
        onChange: @escaping @Sendable ([String]) -> Void
    ) {
        let core = Core(root: Self.real(directory.path), debounce: debounce, isRelevant: isRelevant, onChange: onChange)
        guard core.start() else { return nil }
        self.core = core
    }

    deinit {
        core.stop()
    }

    /// Events name the real path, /var as /private/var. Foundation's symlink resolution
    /// strips /private again, so this is realpath(3).
    static func real(_ path: String) -> String {
        path.withCString { path in realpath(path, nil).map { String(cString: $0) } } ?? path
    }

    /// A path as events name it, relative to the root; nil for the root itself and anything outside it.
    static func relativePath(of path: String, under root: String) -> String? {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix), path.utf8.count > prefix.utf8.count else { return nil }
        let relative = String(path[prefix.endIndex...])
        return relative.hasSuffix("/") ? String(relative.dropLast()) : relative
    }

    /// Whether a relative path is something no one edits by hand: dependencies, hidden entries
    /// (`.git`, `.build`, an editor's swap file) and backup copies.
    static func isIgnored(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { $0 == "node_modules" || $0.hasPrefix(".") || $0.hasSuffix("~") }
    }

    /// The relevant paths among one callback's events, relative to the root. An event that says
    /// others were lost counts as the whole tree.
    static func changes(
        paths: [String],
        flags: [FSEventStreamEventFlags],
        root: String,
        isRelevant: (String) -> Bool
    ) -> Set<String> {
        let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagUserDropped)
        var changed = Set<String>()
        for (index, path) in paths.enumerated() {
            if index < flags.count, flags[index] & lost != 0 {
                changed.insert(everything)
            } else if let relative = relativePath(of: path, under: root), isRelevant(relative) {
                changed.insert(relative)
            }
        }
        return changed
    }

    /// The stream and what it has collected. The stream holds it, so a callback in flight never
    /// finds it gone; `pending` and `scheduled` are only touched on `queue`.
    private final class Core: @unchecked Sendable {
        private let root: String
        private let debounce: TimeInterval
        private let isRelevant: @Sendable (String) -> Bool
        private let onChange: @Sendable ([String]) -> Void
        private let queue = DispatchQueue(label: "floe.directory-watcher", qos: .utility)
        private var stream: FSEventStreamRef?
        private var pending = Set<String>()
        private var scheduled: DispatchWorkItem?

        init(root: String, debounce: TimeInterval, isRelevant: @escaping @Sendable (String) -> Bool, onChange: @escaping @Sendable ([String]) -> Void) {
            self.root = root
            self.debounce = debounce
            self.isRelevant = isRelevant
            self.onChange = onChange
        }

        func start() -> Bool {
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<Core>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<Core>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
            guard let stream = FSEventStreamCreate(
                nil, Self.callback, &context, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0, flags
            ) else { return false }
            // Set before the stream starts: no callback runs earlier, and each one reads it.
            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                self.stream = nil
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                return false
            }
            return true
        }

        /// Stops the stream on its own queue, so no callback can be running when the stream
        /// goes, and nothing collected is reported afterwards.
        func stop() {
            queue.async {
                self.scheduled?.cancel()
                self.scheduled = nil
                guard let stream = self.stream else { return }
                self.stream = nil
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
        }

        private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let core = Unmanaged<Core>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            core.note(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
        }

        private func note(paths: [String], flags: [FSEventStreamEventFlags]) {
            let changed = DirectoryWatcher.changes(paths: paths, flags: flags, root: root, isRelevant: isRelevant)
            guard !changed.isEmpty, stream != nil else { return }
            pending.formUnion(changed)
            scheduled?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.pending.isEmpty else { return }
                let report = self.pending.sorted()
                self.pending = []
                self.scheduled = nil
                self.onChange(report)
            }
            scheduled = work
            queue.asyncAfter(deadline: .now() + debounce, execute: work)
        }
    }
}
