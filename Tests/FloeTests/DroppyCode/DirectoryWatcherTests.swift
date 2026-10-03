//
//  DirectoryWatcherTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Synchronization
import Testing

struct DirectoryWatcherTests {
    private let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
    private let modified = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)

    @Test func aPathIsNamedRelativeToTheRoot() {
        #expect(DirectoryWatcher.relativePath(of: "/ext/hello/src/main.tsx", under: "/ext/hello") == "src/main.tsx")
        #expect(DirectoryWatcher.relativePath(of: "/ext/hello/src/", under: "/ext/hello/") == "src")
    }

    @Test(arguments: ["/ext/hello", "/ext/hello/", "/ext/hello-world/src/main.tsx", "/elsewhere/main.tsx", ""])
    func theRootItselfAndPathsOutsideItHaveNoRelativePath(path: String) {
        #expect(DirectoryWatcher.relativePath(of: path, under: "/ext/hello") == nil)
    }

    @Test(arguments: [
        "node_modules/react/index.js", "src/node_modules/x.js", ".git/HEAD", ".build/debug/x", "src/.main.tsx.swp", ".DS_Store", "src/main.tsx~",
    ])
    func dependenciesHiddenEntriesAndBackupsAreIgnored(path: String) {
        #expect(DirectoryWatcher.isIgnored(path))
    }

    @Test(arguments: ["src/main.tsx", "package.json", "assets/icon.png", "src/my.node_modules.ts", "src/a.b/c.ts"])
    func ordinaryFilesAreNot(path: String) {
        #expect(!DirectoryWatcher.isIgnored(path))
    }

    @Test func oneCallbacksEventsBecomeTheRelevantRelativePaths() {
        let changed = DirectoryWatcher.changes(
            paths: ["/ext/hello/src/main.tsx", "/ext/hello/node_modules/a.js", "/ext/hello", "/other/x.ts", "/ext/hello/src/main.tsx"],
            flags: Array(repeating: modified, count: 5),
            root: "/ext/hello",
            isRelevant: { !DirectoryWatcher.isIgnored($0) }
        )
        #expect(changed == ["src/main.tsx"])
    }

    @Test func anEventThatSaysOthersWereLostCountsAsTheWholeTree() {
        let changed = DirectoryWatcher.changes(paths: ["/ext/hello/node_modules"], flags: [lost], root: "/ext/hello") { _ in false }
        #expect(changed == [DirectoryWatcher.everything])
    }

    @Test func eventsWithoutFlagsAreStillRead() {
        let changed = DirectoryWatcher.changes(paths: ["/ext/hello/a.ts", "/ext/hello/b.ts"], flags: [modified], root: "/ext/hello") { _ in true }
        #expect(changed == ["a.ts", "b.ts"])
    }

    @Test func theRealPathResolvesSymlinksAndKeepsWhatDoesNotExist() {
        #expect(DirectoryWatcher.real("/tmp") == "/private/tmp")
        #expect(DirectoryWatcher.real("/no/such/folder") == "/no/such/folder")
    }

    private func makeFolder(_ subfolders: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-watcher-\(UUID().uuidString)")
        for name in subfolders {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        return folder
    }

    /// The real stream, over a temporary extension folder: a burst of saves is one report, and it
    /// names the source files only. A stream can also report what was written just before it
    /// started, here the folders, so the reports are counted by the file saved.
    @Test(.timeLimit(.minutes(1)))
    func aBurstOfSavesIsReportedOnceWithoutTheIgnoredPaths() async throws {
        let folder = try makeFolder(["src", "node_modules/dep", ".git"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let reports = Mutex<[[String]]>([])
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let watcher = try #require(DirectoryWatcher(directory: folder, debounce: 0.5) { paths in
            reports.withLock { $0.append(paths) }
            if paths.contains("src/main.tsx") {
                continuation.yield()
            }
        })

        for name in ["node_modules/dep/index.js", ".git/index", "src/main.tsx", "src/helper.ts", "src/main.tsx"] {
            try Data(name.utf8).write(to: folder.appendingPathComponent(name))
        }
        for await _ in stream {
            break
        }
        // Long enough for a second report, had the burst been split.
        try await Task.sleep(for: .seconds(1.5))
        withExtendedLifetime(watcher) { /* watched until here */ }

        let seen = reports.withLock(\.self)
        let saves = seen.filter { $0.contains("src/main.tsx") }
        #expect(saves.count == 1)
        #expect(saves.first?.contains("src/helper.ts") == true)
        #expect(seen.joined().allSatisfy { $0.hasPrefix("src") })
    }

    @Test(.timeLimit(.minutes(1)))
    func aSaveThatHasSettledIsNotReportedToAWatcherStartedAfterIt() async throws {
        let folder = try makeFolder(["src"])
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("src/main.tsx"))
        // As long as the debounce a restart waits for before it starts the next watcher.
        try await Task.sleep(for: .milliseconds(300))

        let reports = Mutex<[[String]]>([])
        let watcher = try #require(DirectoryWatcher(directory: folder, debounce: 0.1) { paths in reports.withLock { $0.append(paths) } })
        try await Task.sleep(for: .seconds(1.5))
        withExtendedLifetime(watcher) { /* watched until here */ }
        #expect(reports.withLock(\.self).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aReleasedWatcherReportsNothing() async throws {
        let folder = try makeFolder(["src"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let reports = Mutex<[[String]]>([])
        var watcher = DirectoryWatcher(directory: folder, debounce: 0.2, isRelevant: { $0 == "src/main.tsx" }) { paths in
            reports.withLock { $0.append(paths) }
        }
        #expect(watcher != nil)
        try Data().write(to: folder.appendingPathComponent("src/main.tsx"))
        // Released before the save has settled: what was collected is dropped with the stream.
        watcher = nil
        try await Task.sleep(for: .seconds(1))
        #expect(reports.withLock(\.self).isEmpty)
    }
}
