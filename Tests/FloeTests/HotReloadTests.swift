//
//  HotReloadTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct HotReloadTests {
    private func makeExtension(withSources: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("floe-hot-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if withSources {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
        }
        return folder
    }

    private func command(in folder: URL, source: ExtensionCommand.Source = .local, mode: String = "view") -> ExtensionCommand {
        ExtensionCommand(
            extensionDir: folder, extensionName: "sample", extensionTitle: "Sample", source: source, name: "main", title: "Main",
            mode: mode, interval: nil, icon: nil, arguments: [], extensionPreferences: [], commandPreferences: []
        )
    }

    @Test func aLocalExtensionWithSourcesIsWatchedAtItsFolder() throws {
        let folder = try makeExtension(withSources: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(HotReload.watchedFolder(for: command(in: folder)) == folder)
    }

    @Test func aLocalExtensionWithoutSourcesIsNotWatched() throws {
        let folder = try makeExtension(withSources: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(HotReload.watchedFolder(for: command(in: folder)) == nil)
        // A file named src is not a source folder.
        try Data().write(to: folder.appendingPathComponent("src"))
        #expect(HotReload.watchedFolder(for: command(in: folder)) == nil)
    }

    @Test func anExtensionRaycastInstalledIsNeverWatched() throws {
        let folder = try makeExtension(withSources: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(HotReload.watchedFolder(for: command(in: folder, source: .raycast)) == nil)
    }

    @Test(arguments: ["no-view", "menu-bar"])
    func aCommandWithoutAViewIsNotRunAgainOnASave(mode: String) throws {
        let folder = try makeExtension(withSources: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(HotReload.watchedFolder(for: command(in: folder, mode: mode)) == nil)
    }

    @Test(arguments: ["src/main.tsx", "src/lib/api.ts", "src/data.json", "package.json", "assets/icon.png", DirectoryWatcher.everything])
    func aChangeTheRestartedCommandWouldShowRestartsIt(path: String) {
        #expect(HotReload.restarts(path))
    }

    @Test(arguments: [
        "node_modules/react/index.js", "src/node_modules/x.js", ".git/index", "src/.main.tsx.swp", "src/main.tsx~",
        "dist/main.js", "README.md", "bun.lock", "package-lock.json", "src", "assets", "lib/package.json",
    ])
    func anythingElseDoesNot(path: String) {
        #expect(!HotReload.restarts(path))
    }

    @Test func onlyTheManifestChangesTheCatalog() {
        #expect(HotReload.changesManifest(["src/main.tsx", "package.json"]))
        #expect(HotReload.changesManifest([DirectoryWatcher.everything]))
        #expect(!HotReload.changesManifest(["src/main.tsx", "src/package.json"]))
        #expect(!HotReload.changesManifest([]))
    }
}
